//===- ForwardActivationState.cpp - Activation-local state in SSA ---------===//
//
// Within one activation, a read of state bits that the activation itself wrote
// or read earlier takes that SSA value instead of loading the state again. The
// writes are kept, so update events, change detection and observers see what
// they saw before; only reads disappear. An activation's statements run in
// order (IEEE 1800-2023 4.6) without interleaving (4.7) and blocking updates
// take effect at once (4.9.3), so the read would load exactly that value.
// This keeps a fused body's values in registers instead of round-tripping
// them through the state planes, where a wide load of bytes several narrower
// stores just wrote cannot be forwarded by the CPU.
//
//===----------------------------------------------------------------------===//

#include "../../../Conversion/SimulationToSchedule/NativePipeline.h"
#include "talos/Analysis/ContributionMirrorAnalysis.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/OrderedDenseAnalysis.h"
#include "talos/Analysis/PersistentIntMap.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationResources.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/Statistic.h"

#include <atomic>
#include <map>
#include <memory>

namespace talos {
#define GEN_PASS_DEF_TALOSSIMFORWARDACTIVATIONSTATEPASS
#include "talos/Dialect/Schedule/Transforms/Passes.h.inc"
} // namespace talos

using namespace mlir;

namespace talos {
namespace {

/// A design root: a net (true) or a variable (false), and its descriptor.
using RootKey = std::pair<bool, uint64_t>;
uint64_t keyOf(RootKey root) { return root.second << 1 | uint64_t(root.first); }

/// Root bits [low, high) hold bits [valueLow, valueLow + high - low) of the
/// packed scalar form of `value`.
struct Entry {
  uint64_t high;
  Value value;
  uint64_t valueLow;
  bool operator==(const Entry &other) const {
    return high == other.high && value == other.value &&
           valueLow == other.valueLow;
  }
};
using Bits = std::map<uint64_t, Entry>; // low -> entry, disjoint
/// Known bits per root, keyed by `keyOf`. Persistent, so a program point
/// shares every root its operation leaves alone with the point before.
using State = analysis::PersistentIntMap<Bits>;

/// Must-information at one program point: the root bits whose current value
/// is a known SSA value on every path that reaches it.
class KnownLattice final : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;
  bool reachable = false;
  State state;

  ChangeResult merge(const State &incoming) {
    if (!reachable) {
      reachable = true;
      state = incoming;
      return ChangeResult::Change;
    }
    if (state.sameAs(incoming))
      return ChangeResult::NoChange;
    // Keep only facts that hold on both paths. A value present on every
    // incoming path is defined on every path, so it dominates this point.
    bool changed =
        state.intersectWith(incoming, [](const Bits &mine, const Bits &theirs) {
          std::optional<Bits> meet;
          for (const auto &[low, entry] : mine) {
            auto match = theirs.find(low);
            if (match != theirs.end() && match->second == entry) {
              if (!meet)
                meet.emplace();
              meet->emplace(low, entry);
            }
          }
          return meet;
        });
    return changed ? ChangeResult::Change : ChangeResult::NoChange;
  }
  ChangeResult join(const AbstractDenseLattice &rhs) override {
    const auto &other = static_cast<const KnownLattice &>(rhs);
    return other.reachable ? merge(other.state) : ChangeResult::NoChange;
  }
  void print(raw_ostream &os) const override {
    os << (reachable ? state.size() : 0) << " roots";
  }
};

/// Design facts every function's forwarding reads: built once per design and
/// shared, read-only, by the function passes.
struct StateForwardingFacts {
  explicit StateForwardingFacts(sim::SimDesignOp design) {
    Block &body = design.getBody().front();
    for (auto driver : body.getOps<sim::SimDriverDeclOp>()) {
      driverNets[driver.getId()] = driver.getNetId();
      if (sim::has<sim::metadata::ContributionMirrorsNet>(driver))
        mirrorNets[driver.getId()] = driver.getNetId();
    }
    // IEEE 1800-2023 23.3.3.7: connected nets are one simulated net, so a
    // write of any member changes the others' bits.
    for (auto connection : body.getOps<sim::SimNetConnectDeclOp>()) {
      connectedNets.insert(connection.getLhsNetId());
      connectedNets.insert(connection.getRhsNetId());
    }
    // 28.8, 4.9.5: a drive in a design with pass switches resolves the
    // switch channels at once, changing nets other than the driven one.
    netsKnown = body.getOps<sim::SimPassSwitchDeclOp>().empty();
    // Each function pass derives its own handles, which reads only that
    // function, so the derivation runs in parallel with the forwarding.
    handles = std::make_unique<analysis::HandleDataflowAnalysis>(design);
  }

  /// Net of every driver, and of the contribution mirrors among them, whose
  /// lone strong contribution is the net's value.
  DenseMap<uint64_t, uint64_t> driverNets, mirrorNets;
  /// Nets merged with others; their bits are never known.
  DenseSet<uint64_t> connectedNets;
  /// Whether any net's bits may be known.
  bool netsKnown = true;
  std::unique_ptr<analysis::HandleDataflowAnalysis> handles;
};

std::optional<uint64_t> packedWidth(Type type) {
  if (isa<IntegerType, sim::LogicType>(type) || sim::isAggregateType(type))
    if (auto width = sim::getPackedWidth(type))
      return *width;
  return std::nullopt;
}

/// The width- and state-matched scalar of a packed value type (what
/// `packed.flatten` produces), or the type itself for a scalar.
Type scalarOf(Type type) {
  if (isa<IntegerType, sim::LogicType>(type))
    return type;
  if (sim::isAggregateType(type))
    return sim::getPackedScalarType(type);
  return {};
}

class KnownStateAnalysis final
    : public analysis::OrderedDenseForwardDataFlowAnalysis<KnownLattice> {
public:
  KnownStateAnalysis(DataFlowSolver &solver, const StateForwardingFacts &design,
                     const analysis::HandleFacts &facts)
      : OrderedDenseForwardDataFlowAnalysis(solver), design(design),
        facts(facts) {}

  LogicalResult visitOperation(Operation *op, const KnownLattice &before,
                               KnownLattice *after) override {
    if (!before.reachable)
      return success();
    propagateIfChanged(after, after->merge(transfer(op, before.state)));
    return success();
  }

private:
  void setToEntryState(KnownLattice *lattice) override {
    propagateIfChanged(lattice, lattice->merge(State()));
  }

  /// The root and bits a handle names, when its selection is static.
  std::optional<std::pair<RootKey, std::pair<uint64_t, uint64_t>>>
  sliceOf(Value handle) const {
    auto fact = facts.find(handle);
    if (fact == facts.end() || !fact->second.descriptor ||
        fact->second.dynamic || !fact->second.width)
      return std::nullopt;
    bool net = fact->second.resource == schedule::ComputeResourceKind::Net;
    if (!net && fact->second.resource != schedule::ComputeResourceKind::Storage)
      return std::nullopt;
    return std::make_pair(
        RootKey{net, *fact->second.descriptor},
        std::make_pair(fact->second.low,
                       fact->second.low + fact->second.width));
  }

  State transfer(Operation *op, const State &in) const {
    // A suspension ends the activation: other processes, the scheduler and
    // the runtime may change any state before the next one.
    if (sim::isSuspensionOp(op))
      return State();
    State out = in;
    auto forget = [&](RootKey root, uint64_t low, uint64_t high) {
      const Bits *found = out.find(keyOf(root));
      if (!found)
        return;
      // Drop every entry overlapping [low, high); keep the parts outside.
      Bits bits;
      for (const auto &[start, entry] : *found) {
        if (entry.high <= low || start >= high) {
          bits.emplace(start, entry);
          continue;
        }
        if (start < low)
          bits.emplace(start, Entry{low, entry.value, entry.valueLow});
        if (entry.high > high)
          bits.emplace(high, Entry{entry.high, entry.value,
                                   entry.valueLow + (high - start)});
      }
      if (bits.empty())
        out.erase(keyOf(root));
      else
        out.insert(keyOf(root), std::move(bits));
    };
    auto forgetRoot = [&](RootKey root) { out.erase(keyOf(root)); };
    auto forgetKind = [&](bool net) {
      SmallVector<uint64_t> keys;
      out.forEach([&](uint64_t key, const Bits &) {
        if (bool(key & 1) == net)
          keys.push_back(key);
      });
      for (uint64_t key : keys)
        out.erase(key);
    };
    auto record = [&](RootKey root, uint64_t low, uint64_t high, Value value,
                      bool overwrite) {
      if (!scalarOf(value.getType()) ||
          (root.first &&
           (!design.netsKnown || design.connectedNets.contains(root.second))))
        return forget(root, low, high);
      if (overwrite) {
        forget(root, low, high);
        const Bits *found = out.find(keyOf(root));
        Bits bits = found ? *found : Bits();
        bits.emplace(low, Entry{high, value, 0});
        out.insert(keyOf(root), std::move(bits));
        return;
      }
      // A read fills only the bits no earlier fact already names.
      const Bits *found = out.find(keyOf(root));
      Bits bits = found ? *found : Bits();
      SmallVector<std::pair<uint64_t, uint64_t>> gaps;
      uint64_t cursor = low;
      for (const auto &[start, entry] : bits) {
        if (entry.high <= cursor || start >= high)
          continue;
        if (start > cursor)
          gaps.push_back({cursor, start});
        cursor = std::max(cursor, entry.high);
      }
      if (cursor < high)
        gaps.push_back({cursor, high});
      if (gaps.empty())
        return;
      for (auto [start, stop] : gaps)
        bits.emplace(start, Entry{stop, value, start - low});
      out.insert(keyOf(root), std::move(bits));
    };

    if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op)) {
      auto target = analysis::getStaticDriveTarget(op, drive.getDriver());
      auto width = packedWidth(drive.getValue().getType());
      if (target.id && target.low && width) {
        auto net = design.driverNets.find(*target.id);
        if (net != design.driverNets.end()) {
          RootKey root{true, net->second};
          // IEEE 1800-2023 6.6.1, Table 6-2: a lone strong contribution
          // resolves to its own value, so the net now holds the driven bits.
          if (design.mirrorNets.count(*target.id))
            record(root, *target.low, *target.low + *width, drive.getValue(),
                   true);
          else
            forget(root, *target.low, *target.low + *width);
          return out;
        }
      }
      if (auto slice = sliceOf(drive.getDriver()))
        forgetRoot(slice->first);
      else
        forgetKind(true);
      return out;
    }
    if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
      if (auto slice = sliceOf(store.getReference());
          slice && !slice->first.first)
        record(slice->first, slice->second.first, slice->second.second,
               store.getValue(), true);
      else if (auto fact = facts.find(store.getReference());
               fact != facts.end() && fact->second.descriptor &&
               fact->second.resource == schedule::ComputeResourceKind::Storage)
        forgetRoot({false, *fact->second.descriptor});
      else if (auto fact = facts.find(store.getReference());
               fact != facts.end() &&
               fact->second.resource == schedule::ComputeResourceKind::Local)
        ; // Activation-local storage is not design state.
      else
        forgetKind(false);
      return out;
    }
    if (auto read = dyn_cast<sim::SimNetReadOp>(op)) {
      if (auto slice = sliceOf(read.getNet()); slice && slice->first.first)
        record(slice->first, slice->second.first, slice->second.second,
               read.getResult(), false);
      return out;
    }
    if (auto load = dyn_cast<sim::SimRefLoadOp>(op)) {
      if (auto slice = sliceOf(load.getReference());
          slice && !slice->first.first)
        record(slice->first, slice->second.first, slice->second.second,
               load.getResult(), false);
      return out;
    }
    // Everything else: operations that cannot write design state keep the
    // facts; any possible write forgets what it may change.
    if (isMemoryEffectFree(op) && op->getNumRegions() == 0)
      return in;
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects || op->getNumRegions() != 0)
      return State();
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    for (const auto &instance : instances) {
      if (isa<MemoryEffects::Read>(instance.getEffect()))
        continue;
      SideEffects::Resource *resource = instance.getResource();
      if (resource == sim::NetResource::get() ||
          resource == sim::StorageResource::get()) {
        bool net = resource == sim::NetResource::get();
        if (Value handle = instance.getValue())
          if (auto slice = sliceOf(handle);
              slice && slice->first.first == net) {
            forget(slice->first, slice->second.first, slice->second.second);
            continue;
          }
        forgetKind(net);
        continue;
      }
      // IEEE 1800-2023 35.5.3: a context import may call exported subroutines
      // or VPI, which may write any state.
      if (resource == sim::ExternalResource::get())
        if (auto dpi = dyn_cast<sim::SimDPICallOp>(op);
            dpi && dpi.getIsContext())
          return State();
      // Writes to the scheduler, heap, I/O and other runtime resources do
      // not change design state now; NBA updates apply in a later region
      // (4.9.4). An unnamed resource may be anything.
      if (resource == SideEffects::DefaultResource::get() ||
          resource == SideEffects::AutomaticAllocationScopeResource::get())
        return State();
    }
    return out;
  }

  const StateForwardingFacts &design;
  const analysis::HandleFacts &facts;
};

/// Whether bits [low, low + width) of the scalar form of `value` can be
/// materialized as `type`, which needs the same representation.
bool canMaterialize(Value value, uint64_t low, uint64_t width, Type type) {
  Type scalar = scalarOf(value.getType());
  Type target = scalarOf(type);
  if (!scalar || !target ||
      isa<IntegerType>(scalar) != isa<IntegerType>(target))
    return false;
  auto scalarWidth = sim::getPackedWidth(scalar);
  auto targetWidth = sim::getPackedWidth(target);
  return scalarWidth && targetWidth && *targetWidth == width &&
         low + width <= *scalarWidth;
}

/// Bits [low, low + width) of the scalar form of `value`, as `type`; see
/// `canMaterialize`. Integer selections take the canonical shrui/trunci form
/// and logic ones `logic.extract`, as the frontend and canonicalizer build
/// them; later lowering assembles wide integers into words.
Value materialize(OpBuilder &builder, Location location, Value value,
                  uint64_t low, uint64_t width, Type type) {
  Type scalar = scalarOf(value.getType());
  Type target = scalarOf(type);
  Value bits = value;
  if (bits.getType() != scalar)
    bits = sim::SimPackedFlattenOp::create(builder, location, scalar, bits);
  if (low != 0 || width != *sim::getPackedWidth(scalar)) {
    if (auto integer = dyn_cast<IntegerType>(scalar)) {
      if (low)
        bits = arith::ShRUIOp::create(
            builder, location, bits,
            arith::ConstantOp::create(builder, location, integer,
                                      builder.getIntegerAttr(integer, low)));
      bits = arith::TruncIOp::create(builder, location, target, bits);
    } else {
      bits = sim::SimLogicExtractOp::create(builder, location, target, bits,
                                            builder.getI64IntegerAttr(low));
    }
  }
  if (bits.getType() != type)
    bits = sim::SimPackedUnflattenOp::create(builder, location, type, bits);
  return bits;
}

struct FunctionResult {
  uint64_t reads = 0, extracts = 0;
};

FunctionResult forwardFunction(sim::SimFuncOp function,
                               const StateForwardingFacts &design) {
  FunctionResult result;
  if (function.getBody().empty())
    return result;
  analysis::HandleDataflowResult handles = design.handles->analyze(function);
  // Calls are opaque: the callee may write any state (13.3, 13.4).
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
  solver.load<dataflow::DeadCodeAnalysis>();
  solver.load<dataflow::SparseConstantPropagation>();
  solver.load<KnownStateAnalysis>(design, handles.facts);
  if (failed(solver.initializeAndRun(function)))
    return result;

  SmallVector<Operation *> reads;
  function.walk([&](Operation *op) {
    if (isa<sim::SimNetReadOp, sim::SimRefLoadOp>(op))
      reads.push_back(op);
  });
  // The join keeps facts from live edges only, and region exits pass their
  // facts on: a known value may not dominate a read behind a dead edge or
  // after a region, and then stays unused.
  DominanceInfo dominance(function);
  SmallVector<Operation *> touched;
  for (Operation *read : reads) {
    if (read->use_empty())
      continue;
    auto *lattice =
        solver.lookupState<KnownLattice>(solver.getProgramPointBefore(read));
    if (!lattice || !lattice->reachable)
      continue;
    Value handle = read->getOperand(0);
    auto fact = handles.facts.find(handle);
    if (fact == handles.facts.end() || !fact->second.descriptor ||
        fact->second.dynamic || !fact->second.width)
      continue;
    bool net = isa<sim::SimNetReadOp>(read);
    const Bits *known =
        lattice->state.find(keyOf({net, *fact->second.descriptor}));
    if (!known)
      continue;
    const Bits &bits = *known;
    OpBuilder builder(read);
    // Replace `value` (root bits [low, low + width)) when the facts cover it
    // without a gap: each fact supplies its bits, concatenated in order.
    auto replace = [&](Value value, uint64_t low, uint64_t width) {
      Type target = scalarOf(value.getType());
      if (!target)
        return false;
      bool integer = isa<IntegerType>(target);
      auto it = bits.upper_bound(low);
      if (it == bits.begin())
        return false;
      --it;
      SmallVector<std::tuple<Value, uint64_t, uint64_t>> pieces;
      for (uint64_t cursor = low; cursor < low + width; ++it) {
        if (it == bits.end() || it->first > cursor || it->second.high <= cursor)
          return false;
        uint64_t stop = std::min(it->second.high, low + width);
        pieces.emplace_back(it->second.value,
                            it->second.valueLow + (cursor - it->first),
                            stop - cursor);
        cursor = stop;
      }
      auto pieceType = [&](uint64_t count) -> Type {
        if (pieces.size() == 1)
          return value.getType();
        return integer ? Type(builder.getIntegerType(count))
                       : Type(sim::LogicType::get(read->getContext(), count));
      };
      // Check every piece before building anything.
      for (auto [source, from, count] : pieces)
        if (!dominance.properlyDominates(source, read) ||
            !canMaterialize(source, from, count, pieceType(count)))
          return false;
      Location location = read->getLoc();
      SmallVector<Value> parts; // least significant first
      for (auto [source, from, count] : pieces)
        parts.push_back(materialize(builder, location, source, from, count,
                                    pieceType(count)));
      Value known = parts.front();
      if (parts.size() > 1) {
        // Concatenate like the frontend: integers as or(shl(zext)) trees,
        // logic values with `logic.concat`, most significant first.
        if (integer) {
          uint64_t shift = 0;
          for (auto [index, part] : llvm::enumerate(parts)) {
            Value wide =
                arith::ExtUIOp::create(builder, location, target, part);
            if (shift)
              wide = arith::ShLIOp::create(
                  builder, location, wide,
                  arith::ConstantOp::create(
                      builder, location, target,
                      builder.getIntegerAttr(target, shift)));
            known = index ? arith::OrIOp::create(builder, location, known, wide)
                                .getResult()
                          : wide;
            shift += cast<IntegerType>(part.getType()).getWidth();
          }
        } else {
          SmallVector<Value> mostFirst(llvm::reverse(parts));
          known = sim::SimLogicConcatOp::create(builder, location, target,
                                                mostFirst);
        }
        if (known.getType() != value.getType())
          known = sim::SimPackedUnflattenOp::create(builder, location,
                                                    value.getType(), known);
      }
      value.replaceAllUsesWith(known);
      return true;
    };
    uint64_t low = fact->second.low;
    if (replace(read->getResult(0), low, fact->second.width)) {
      ++result.reads;
      touched.push_back(read);
      continue;
    }
    // Otherwise forward the constant subelements that are known.
    std::function<void(Value, uint64_t)> visit = [&](Value value,
                                                     uint64_t base) {
      for (Operation *user : llvm::make_early_inc_range(value.getUsers())) {
        auto extract = dyn_cast<sim::SimAggregateExtractOp>(user);
        if (!extract || !sim::getPackedWidth(value.getType()))
          continue;
        auto sub = sim::getAggregateProvenanceSubelement(
            value.getType(), unsigned(extract.getIndex()));
        if (!sub)
          continue;
        if (replace(extract.getResult(), base + sub->first, sub->second)) {
          ++result.extracts;
          touched.push_back(read);
        } else {
          visit(extract.getResult(), base + sub->first);
        }
      }
    };
    visit(read->getResult(0), low);
  }
  // Erase what forwarding left without uses: extract trees bottom-up, then
  // the reads.
  std::function<void(Operation *)> sweep = [&](Operation *op) {
    for (Operation *user : llvm::make_early_inc_range(op->getUsers()))
      if (isa<sim::SimAggregateExtractOp>(user))
        sweep(user);
    if (op->use_empty())
      op->erase();
  };
  llvm::SmallPtrSet<Operation *, 8> swept;
  for (Operation *read : touched)
    if (swept.insert(read).second)
      sweep(read);
  return result;
}

class ForwardActivationStateFunctionPass final
    : public PassWrapper<ForwardActivationStateFunctionPass,
                         OperationPass<sim::SimFuncOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(
      ForwardActivationStateFunctionPass)
  ForwardActivationStateFunctionPass(
      std::shared_ptr<const StateForwardingFacts> facts,
      std::shared_ptr<std::atomic<uint64_t>> reads,
      std::shared_ptr<std::atomic<uint64_t>> extracts)
      : facts(std::move(facts)), reads(std::move(reads)),
        extracts(std::move(extracts)) {}
  StringRef getArgument() const final {
    return "talos-sim-forward-activation-state-function";
  }
  void runOnOperation() override {
    FunctionResult result = forwardFunction(getOperation(), *facts);
    *reads += result.reads;
    *extracts += result.extracts;
    if (!result.reads && !result.extracts)
      markAllAnalysesPreserved();
  }

private:
  std::shared_ptr<const StateForwardingFacts> facts;
  std::shared_ptr<std::atomic<uint64_t>> reads, extracts;
};

class TalosSimForwardActivationStatePass final
    : public impl::TalosSimForwardActivationStatePassBase<
          TalosSimForwardActivationStatePass> {
public:
  using Base::Base;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    // Only the function bodies of the design change, by replacing reads with
    // the values they would load: actors, captures, storage, frames and the
    // frozen bytecode stay valid, and so does the native pipeline state.
    markAnalysesPreserved<detail::NativePipelineAnalysis>();
    auto level = native::get<native::OptimizationLevel>(module);
    if (!level || level.getInt() < 1)
      return markAllAnalysesPreserved();
    // 10.6.1, 10.6.2: an assigned or forced variable or net ignores the
    // writes forwarding would pass on until it is deassigned or released.
    if (module
            .walk([](Operation *op) {
              return isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
                         sim::SimReleaseOverrideOp>(op)
                         ? WalkResult::interrupt()
                         : WalkResult::advance();
            })
            .wasInterrupted())
      return markAllAnalysesPreserved();
    auto reads = std::make_shared<std::atomic<uint64_t>>(0);
    auto extracts = std::make_shared<std::atomic<uint64_t>>(0);
    for (auto design : module.getOps<sim::SimDesignOp>()) {
      if (design.getBody().empty())
        continue;
      // IEEE 1800-2023 38.34: a writable VPI client may put or force any
      // value between an activation's writes and reads.
      auto graph = design.getComputeGraphAttr();
      if (!graph || graph.getVpi() == schedule::ComputeVPIMode::Full)
        continue;
      auto facts = std::make_shared<const StateForwardingFacts>(design);
      OpPassManager functions(sim::SimDesignOp::getOperationName());
      functions.addNestedPass<sim::SimFuncOp>(
          std::make_unique<ForwardActivationStateFunctionPass>(facts, reads,
                                                               extracts));
      if (failed(runPipeline(functions, design)))
        return signalPassFailure();
    }
    forwardedReads += *reads;
    forwardedExtracts += *extracts;
  }

private:
  Statistic forwardedReads{this, "forwarded-reads",
                           "state reads replaced by known SSA values"};
  Statistic forwardedExtracts{
      this, "forwarded-extracts",
      "subelements of state reads replaced by known SSA values"};
};

} // namespace
} // namespace talos
