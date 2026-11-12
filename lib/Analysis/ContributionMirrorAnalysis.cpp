//===- ContributionMirrorAnalysis.cpp - Drivers whose slot equals the net -===//

#include "talos/Analysis/ContributionMirrorAnalysis.h"

#include "talos/Analysis/NetConnectivityAnalysis.h"
#include "talos/Analysis/SimulationAnalysis.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/DenseMap.h"

#include <limits>

using namespace mlir;

namespace talos::analysis {
namespace {

std::optional<uint64_t> getStaticDriverOffset(Value value, uint64_t driverID,
                                              DenseSet<Value> &active) {
  if (!value || !active.insert(value).second)
    return std::nullopt;
  auto finish = [&](std::optional<uint64_t> result) {
    active.erase(value);
    return result;
  };
  if (auto context = value.getDefiningOp<sim::SimContextDriverOp>())
    return finish(context.getId() == driverID ? std::optional<uint64_t>(0)
                                              : std::nullopt);
  if (auto extract = value.getDefiningOp<sim::SimDriverExtractOp>()) {
    std::optional<uint64_t> base =
        getStaticDriverOffset(extract.getInput(), driverID, active);
    int64_t rawLow = extract.getLowBit();
    if (!base || rawLow < 0 ||
        static_cast<uint64_t>(rawLow) > UINT64_MAX - *base)
      return finish(std::nullopt);
    return finish(*base + static_cast<uint64_t>(rawLow));
  }
  if (auto subelement = value.getDefiningOp<sim::SimDriverSubelementOp>()) {
    std::optional<uint64_t> base =
        getStaticDriverOffset(subelement.getInput(), driverID, active);
    if (!base)
      return finish(std::nullopt);
    Type current = subelement.getInput().getType().getElementType();
    uint64_t offset = 0;
    for (int64_t rawIndex : subelement.getIndices()) {
      if (rawIndex < 0 || static_cast<uint64_t>(rawIndex) >=
                              sim::getAggregateNumElements(current))
        return finish(std::nullopt);
      auto child = sim::getAggregateProvenanceSubelement(
          current, static_cast<unsigned>(rawIndex));
      if (!child || child->first > UINT64_MAX - offset)
        return finish(std::nullopt);
      offset += child->first;
      current = sim::getAggregateElementType(current,
                                             static_cast<unsigned>(rawIndex));
    }
    if (offset > UINT64_MAX - *base)
      return finish(std::nullopt);
    return finish(*base + offset);
  }
  auto argument = dyn_cast<BlockArgument>(value);
  if (!argument)
    return finish(std::nullopt);
  Block *block = argument.getOwner();
  auto function = dyn_cast<sim::SimFuncOp>(block->getParentOp());
  if (!function || block != &function.getBody().front())
    return finish(std::nullopt);
  auto descriptor = function.getArgAttrOfType<IntegerAttr>(
      argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
  auto low = function.getArgAttrOfType<IntegerAttr>(
      argument.getArgNumber(), sim::metadata::DescriptorLow::getNameStr());
  if (!descriptor || descriptor.getValue().isNegative() ||
      descriptor.getValue().getActiveBits() > 64 ||
      descriptor.getValue().getZExtValue() != driverID ||
      (low &&
       (low.getValue().isNegative() || low.getValue().getActiveBits() > 64)))
    return finish(std::nullopt);
  return finish(low ? low.getValue().getZExtValue() : uint64_t{0});
}

std::optional<StaticDriverTarget>
getExactStaticDriverTarget(Value value, DenseSet<Value> &active, bool &cycle) {
  if (!active.insert(value).second) {
    cycle = true;
    return std::nullopt;
  }
  auto done = [&](std::optional<StaticDriverTarget> result) {
    active.erase(value);
    return result;
  };
  if (auto context = value.getDefiningOp<sim::SimContextDriverOp>())
    return done(StaticDriverTarget{context.getId(), 0});

  Operation *definition = value.getDefiningOp();
  uint64_t addedLowBit = 0;
  Value input;
  if (auto extract = dyn_cast_or_null<sim::SimDriverExtractOp>(definition)) {
    addedLowBit = extract.getLowBit();
    input = extract.getInput();
  } else if (auto subelement =
                 dyn_cast_or_null<sim::SimDriverSubelementOp>(definition)) {
    Type current = subelement.getInput().getType().getElementType();
    for (int64_t rawIndex : subelement.getIndices()) {
      if (rawIndex < 0 || static_cast<uint64_t>(rawIndex) >=
                              sim::getAggregateNumElements(current))
        return done(std::nullopt);
      auto item = sim::getAggregateProvenanceSubelement(
          current, static_cast<unsigned>(rawIndex));
      if (!item ||
          item->first > std::numeric_limits<uint64_t>::max() - addedLowBit)
        return done(std::nullopt);
      addedLowBit += item->first;
      current = sim::getAggregateElementType(current,
                                             static_cast<unsigned>(rawIndex));
    }
    input = subelement.getInput();
  }
  if (input) {
    auto target = getExactStaticDriverTarget(input, active, cycle);
    if (!target ||
        target->lowBit > std::numeric_limits<uint64_t>::max() - addedLowBit)
      return done(std::nullopt);
    target->lowBit += addedLowBit;
    return done(target);
  }

  auto argument = dyn_cast<BlockArgument>(value);
  if (!argument)
    return done(std::nullopt);
  if (auto function =
          dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp())) {
    if (argument.getOwner() == &function.getBody().front()) {
      // A driver capture is the whole descriptor: the function verifier
      // rejects driver views, so the argument starts at bit 0.
      auto descriptor = function.getArgAttrOfType<IntegerAttr>(
          argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
      if (descriptor)
        return done(
            StaticDriverTarget{static_cast<uint64_t>(descriptor.getInt()), 0});
    }
  }

  // CFG cleanup may forward a concrete driver through conditional block
  // arguments after compute fusion. Preserve exactness only when every
  // incoming edge names the same statically-derived driver slice.
  std::optional<StaticDriverTarget> resolved;
  bool sawIncoming = false;
  bool sawCycle = false;
  Block *block = argument.getOwner();
  for (Block *predecessor : block->getPredecessors()) {
    Operation *terminator = predecessor->getTerminator();
    auto branch = dyn_cast<BranchOpInterface>(terminator);
    if (!branch)
      return done(std::nullopt);
    for (unsigned successor = 0; successor != terminator->getNumSuccessors();
         ++successor) {
      if (terminator->getSuccessor(successor) != block)
        continue;
      SuccessorOperands operands = branch.getSuccessorOperands(successor);
      unsigned index = argument.getArgNumber();
      if (index >= operands.size() || operands.isOperandProduced(index))
        return done(std::nullopt);
      bool incomingCycle = false;
      auto incoming =
          getExactStaticDriverTarget(operands[index], active, incomingCycle);
      if (!incoming && incomingCycle) {
        sawCycle = true;
        continue;
      }
      if (!incoming || (resolved && !(*resolved == *incoming)))
        return done(std::nullopt);
      resolved = incoming;
      sawIncoming = true;
    }
  }
  if (!resolved && sawCycle)
    cycle = true;
  return done(sawIncoming ? resolved : std::nullopt);
}

} // namespace

std::optional<uint64_t> getStaticDriverOffset(Value driver, uint64_t driverID) {
  DenseSet<Value> active;
  return getStaticDriverOffset(driver, driverID, active);
}

std::optional<StaticDriverTarget> getExactStaticDriverTarget(Value driver) {
  DenseSet<Value> active;
  bool cycle = false;
  return getExactStaticDriverTarget(driver, active, cycle);
}

std::optional<uint64_t> getStaticDriverID(Value value) {
  while (value) {
    if (auto context = value.getDefiningOp<sim::SimContextDriverOp>())
      return context.getId();
    Operation *definition = value.getDefiningOp();
    if (auto extract = dyn_cast_or_null<sim::SimDriverExtractOp>(definition)) {
      value = extract.getInput();
      continue;
    }
    if (auto extract =
            dyn_cast_or_null<sim::SimDriverDynExtractOp>(definition)) {
      value = extract.getInput();
      continue;
    }
    if (auto subelement =
            dyn_cast_or_null<sim::SimDriverSubelementOp>(definition)) {
      value = subelement.getInput();
      continue;
    }
    if (auto element =
            dyn_cast_or_null<sim::SimDriverArrayElementOp>(definition)) {
      value = element.getInput();
      continue;
    }
    auto argument = dyn_cast<BlockArgument>(value);
    if (!argument)
      return std::nullopt;
    auto function =
        dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
    if (!function || argument.getOwner() != &function.getBody().front())
      return std::nullopt;
    auto descriptor = function.getArgAttrOfType<IntegerAttr>(
        argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
    return descriptor ? std::optional<uint64_t>(descriptor.getInt())
                      : std::nullopt;
  }
  return std::nullopt;
}

StaticDriveTarget getStaticDriveTarget(Operation *drive, Value driver) {
  StaticDriveTarget result;
  std::optional<StaticDriverTarget> exact;
  auto frozenID = schedule::get<schedule::Field::ExactDriverId>(drive);
  auto frozenLow = schedule::get<schedule::Field::ExactDriverLow>(drive);
  if (frozenID && frozenLow && !frozenID.getValue().isNegative() &&
      !frozenLow.getValue().isNegative() &&
      frozenID.getValue().getActiveBits() <= 64 &&
      frozenLow.getValue().getActiveBits() <= 64)
    exact = StaticDriverTarget{frozenID.getValue().getZExtValue(),
                               frozenLow.getValue().getZExtValue()};
  else if (!frozenID && !frozenLow)
    exact = getExactStaticDriverTarget(driver);
  result.id =
      exact ? std::optional<uint64_t>(exact->id) : getStaticDriverID(driver);
  if (!result.id)
    return result;
  result.exact = exact.has_value();
  result.low = exact ? std::optional<uint64_t>(exact->lowBit)
                     : getStaticDriverOffset(driver, *result.id);
  return result;
}

/// The net descriptor a net handle names, through constant views.
static std::optional<uint64_t> getStaticNetID(Value value) {
  while (value) {
    if (auto context = value.getDefiningOp<sim::SimContextNetOp>())
      return context.getId();
    if (auto extract = value.getDefiningOp<sim::SimNetExtractOp>()) {
      value = extract.getInput();
      continue;
    }
    auto argument = dyn_cast<BlockArgument>(value);
    if (!argument)
      return std::nullopt;
    auto function =
        dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
    if (!function || argument.getOwner() != &function.getBody().front())
      return std::nullopt;
    auto descriptor = function.getArgAttrOfType<IntegerAttr>(
        argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
    if (!descriptor || descriptor.getValue().isNegative() ||
        descriptor.getValue().getActiveBits() > 64)
      return std::nullopt;
    return descriptor.getValue().getZExtValue();
  }
  return std::nullopt;
}

DenseSet<uint64_t> computeContributionMirrorDrivers(sim::SimDesignOp design) {
  DenseSet<uint64_t> mirrors;
  if (!design || design.getBody().empty())
    return mirrors;
  std::shared_ptr<const IsolatedWireDriverTopology> topology =
      getIsolatedWireDriverTopology(design);
  // [low, high) of each candidate within its net's provenance span.
  DenseMap<uint64_t, std::pair<uint64_t, uint64_t>> candidates;
  for (auto driver : design.getBody().front().getOps<sim::SimDriverDeclOp>()) {
    uint64_t net = driver.getNetId();
    // Every driver of these nets is a strong contribution that overlaps no
    // other one (28.11), on a plain wire (6.6.1; not 6.6.2-6.6.6) with no
    // net delay (28.16), collapsed port alias (23.3.3.7), user-defined
    // nettype (6.6.7) or pass switch (28.8).
    if (!topology->partitionedDriverNets.contains(net) &&
        !topology->sparseDriverRanges.contains(net))
      continue;
    // A conditional gate's polarity banks (28.6) combine at the second drive
    // (28.12); a user net driver feeds a resolution function (6.6.7).
    if (sim::has<sim::metadata::StrengthGroup>(driver) ||
        sim::has<sim::metadata::StrengthBank>(driver) ||
        sim::has<sim::metadata::UserNetDriver>(driver))
      continue;
    auto range = topology->driverRanges.find(driver.getId());
    if (range == topology->driverRanges.end())
      continue;
    candidates[driver.getId()] = range->second;
  }
  if (candidates.empty())
    return mirrors;

  DenseSet<uint64_t> disqualified;
  // Nets some operation may resolve or overwrite without the drivers' own
  // values: every candidate on them keeps its slot.
  DenseSet<uint64_t> excludedNets;
  WalkResult walked = design.walk([&](Operation *operation) {
    // IEEE 1800-2023 10.6.2: release restores the value of the drivers,
    // which only their slots hold while a net is forced.
    if (isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
            sim::SimReleaseOverrideOp>(operation))
      return WalkResult::interrupt();
    // A direct write (a user-defined resolution, 6.6.7, or a UPF corruption)
    // replaces the resolved value without changing any contribution.
    if (auto write = dyn_cast<sim::SimNetWriteOp>(operation)) {
      std::optional<uint64_t> net = getStaticNetID(write.getNet());
      if (!net)
        return WalkResult::interrupt();
      excludedNets.insert(*net);
      return WalkResult::advance();
    }
    if (llvm::none_of(operation->getOperandTypes(),
                      [](Type type) { return isa<sim::DriverType>(type); }))
      return WalkResult::advance();
    if (isa<sim::SimDriverExtractOp, sim::SimDriverDynExtractOp,
            sim::SimDriverSubelementOp, sim::SimDriverArrayElementOp>(
            operation))
      return WalkResult::advance();
    Value driver, value;
    if (auto drive = dyn_cast<sim::SimDriverDriveOp>(operation)) {
      driver = drive.getDriver();
      value = drive.getValue();
    } else if (auto drive = dyn_cast<sim::SimDriverDriveChangedOp>(operation)) {
      driver = drive.getDriver();
      value = drive.getValue();
    }
    if (driver) {
      StaticDriveTarget target = getStaticDriveTarget(operation, driver);
      if (!target.id)
        return WalkResult::interrupt();
      std::optional<unsigned> width =
          getSimulationStorageBitWidth(value.getType());
      // Without a constant slice, native lowering resolves every bit of the
      // net from the slots of all its drivers.
      if (!target.low || !width) {
        auto net = topology->driverNets.find(*target.id);
        if (net == topology->driverNets.end())
          return WalkResult::interrupt();
        excludedNets.insert(net->second);
      }
      auto candidate = candidates.find(*target.id);
      if (candidate == candidates.end())
        return WalkResult::advance();
      auto [low, high] = candidate->second;
      // A write into undriven padding would leave the resolver reading the
      // slot itself.
      if (!target.low || !width || *target.low < low || *target.low > high ||
          *width > high - *target.low ||
          schedule::has<schedule::Field::DeferNetResolution>(operation) ||
          sim::has<sim::metadata::UserNetRawDrive>(operation))
        disqualified.insert(*target.id);
      return WalkResult::advance();
    }
    // Call arguments and branch successor operands only forward a driver;
    // each use at the destination is checked on its own. Every other driver
    // operand reads the slot or schedules a write to it: `driver.read`
    // (sequential UDP state, strength-pair and timing-path history), the
    // watched handles of a suspension, inertial, delayed-net and NBA drives.
    DenseSet<unsigned> forwarded;
    auto forward = [&](OperandRange operands) {
      if (!operands.empty())
        for (unsigned index = 0; index != operands.size(); ++index)
          forwarded.insert(operands.getBeginOperandIndex() + index);
    };
    if (auto call = dyn_cast<CallOpInterface>(operation))
      forward(call.getArgOperands());
    if (auto branch = dyn_cast<BranchOpInterface>(operation))
      for (unsigned successor = 0; successor != operation->getNumSuccessors();
           ++successor)
        forward(branch.getSuccessorOperands(successor).getForwardedOperands());
    for (OpOperand &operand : operation->getOpOperands()) {
      if (!isa<sim::DriverType>(operand.get().getType()) ||
          forwarded.contains(operand.getOperandNumber()))
        continue;
      std::optional<uint64_t> id = getStaticDriverID(operand.get());
      if (!id)
        return WalkResult::interrupt();
      disqualified.insert(*id);
    }
    return WalkResult::advance();
  });
  if (walked.wasInterrupted())
    return mirrors;
  for (const auto &[id, range] : candidates)
    if (!disqualified.contains(id) &&
        !excludedNets.contains(topology->driverNets.lookup(id)))
      mirrors.insert(id);
  return mirrors;
}

} // namespace talos::analysis
