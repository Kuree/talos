// Power guards and corruption writes remain visible to subsequent analyses.
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"
using namespace mlir;
namespace talos {
namespace {
struct Descriptor {
  uint64_t id;
  Type type;
  bool net = false, driver = false;
};
bool contains(upf::UPFDomainOp domain, StringRef path) {
  for (Attribute element : domain.getElements()) {
    StringRef prefix = cast<StringAttr>(element).getValue();
    if (path == prefix || (path.starts_with(prefix) &&
                           path.drop_front(prefix.size()).starts_with('.')))
      return true;
  }
  return false;
}
Value handle(OpBuilder &b, Location loc, Value context, Descriptor d) {
  if (d.driver)
    return sim::SimContextDriverOp::create(
        b, loc, sim::DriverType::get(b.getContext(), d.type), context, d.id);
  if (d.net)
    return sim::SimContextNetOp::create(
        b, loc, sim::NetType::get(b.getContext(), d.type), context, d.id);
  return sim::SimContextStorageOp::create(
      b, loc, sim::RefType::get(b.getContext(), d.type), context, d.id);
}
Value load(OpBuilder &b, Location loc, Value reference) {
  if (auto net = dyn_cast<sim::NetType>(reference.getType()))
    return sim::SimNetReadOp::create(b, loc, net.getElementType(), reference);
  return sim::SimRefLoadOp::create(
      b, loc, cast<sim::RefType>(reference.getType()).getElementType(),
      reference);
}
void store(OpBuilder &b, Location loc, Value reference, Value value) {
  if (isa<sim::DriverType>(reference.getType()))
    sim::SimDriverDriveOp::create(b, loc, reference, value);
  else if (isa<sim::NetType>(reference.getType()))
    sim::SimNetWriteOp::create(b, loc, reference, value);
  else
    sim::SimRefStoreOp::create(b, loc, value, reference);
}
Value logicConstant(OpBuilder &b, Location loc, sim::LogicType type, bool value,
                    bool unknown = false) {
  auto integer = b.getIntegerType(type.getWidth());
  return sim::SimLogicConstantOp::create(
      b, loc, type,
      b.getIntegerAttr(integer, value ? APInt::getAllOnes(type.getWidth())
                                      : APInt(type.getWidth(), 0)),
      b.getIntegerAttr(integer, unknown ? APInt::getAllOnes(type.getWidth())
                                        : APInt(type.getWidth(), 0)));
}
bool supportedState(Type type) {
  if (auto array = dyn_cast<sim::PackedArrayType>(type))
    return supportedState(array.getElementType());
  return isa<sim::LogicType, IntegerType>(type);
}
Value flatten(OpBuilder &b, Location loc, Value value) {
  Type scalar = sim::getPackedScalarType(value.getType());
  if (scalar == value.getType())
    return value;
  return sim::SimPackedFlattenOp::create(b, loc, scalar, value);
}
Value corrupt(OpBuilder &b, Location loc, Type type) {
  if (Type scalar = sim::getPackedScalarType(type); scalar != type) {
    Value value = corrupt(b, loc, scalar);
    return sim::SimPackedUnflattenOp::create(b, loc, type, value);
  }
  if (auto logic = dyn_cast<sim::LogicType>(type))
    return logicConstant(b, loc, logic, false, true);
  return arith::ConstantOp::create(b, loc, type, b.getZeroAttr(type));
}
Value equalsLevel(OpBuilder &b, Location loc, Value value, bool high) {
  value = flatten(b, loc, value);
  if (auto logic = dyn_cast<sim::LogicType>(value.getType()))
    return sim::SimLogicCompareOp::create(b, loc, b.getI1Type(),
                                          sim::CompareKind::CaseEq, value,
                                          logicConstant(b, loc, logic, high));
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, value,
                               arith::ConstantIntOp::create(b, loc, high, 1));
}
Value powerOn(OpBuilder &b, Location loc, Value context, Descriptor control,
              bool high) {
  // Initial 6.22 switch slice: input rails are assumed FULL_ON. General supply
  // initialization/evaluation (9.2.1-9.2.3) remains outside this prototype.
  return equalsLevel(b, loc, load(b, loc, handle(b, loc, context, control)),
                     high);
}
Value logicSelect(OpBuilder &b, Location loc, Value condition, Value yes,
                  Value no) {
  Value logic = sim::SimLogicFromBitsOp::create(
      b, loc, sim::LogicType::get(b.getContext(), 1), condition);
  return sim::SimLogicMuxOp::create(b, loc, yes.getType(), logic, yes, no);
}
struct Lowering {
  sim::SimDesignOp design;
  OpBuilder builder;
  uint64_t nextStorage = 0, nextUnit = 0;
  llvm::StringMap<Descriptor> descriptors;
  llvm::DenseMap<uint64_t, std::string> unitPaths;
  sim::SimFuncOp root;
  Lowering(sim::SimDesignOp design)
      : design(design), builder(design.getContext()) {
    for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
      nextStorage = std::max(nextStorage, decl.getId() + 1);
      if (auto name = decl.getHierarchicalName())
        descriptors[*name] = {decl.getId(), decl.getType()};
    }
    for (auto decl : design.getOps<sim::SimNetDeclOp>())
      if (auto name = decl.getHierarchicalName())
        descriptors[*name] = {decl.getId(), decl.getType(), true};
    for (auto decl : design.getOps<sim::SimCodeUnitDeclOp>()) {
      nextUnit = std::max(nextUnit, decl.getId() + 1);
      unitPaths[decl.getId()] = decl.getHierarchicalName().str();
    }
    for (auto fn : design.getOps<sim::SimFuncOp>())
      if (fn.getEntryKind() == sim::EntryKind::RootInitializer)
        root = fn;
  }
  sim::SimFuncOp function(Location loc, StringRef name, ArrayRef<Type> inputs,
                          sim::EntryKind kind) {
    builder.setInsertionPointToEnd(&design.getBody().front());
    uint64_t id = nextUnit++;
    sim::SimCodeUnitDeclOp::create(
        builder, loc, id, uint64_t{0}, kind, builder.getStringAttr(name),
        builder.getStringAttr(name), builder.getUnitAttr());
    SmallVector<NamedAttribute> attrs{
        builder.getNamedAttr("code_unit_id", builder.getI64IntegerAttr(id)),
        builder.getNamedAttr("internal", builder.getUnitAttr()),
        sim::named<sim::metadata::HierarchicalName>(
            builder.getStringAttr(name))};
    SmallVector<DictionaryAttr> args;
    for (size_t i = 0; i < inputs.size(); ++i)
      args.push_back(builder.getDictionaryAttr(
          {sim::named<sim::metadata::CaptureKind>(sim::CaptureKindAttr::get(
              builder.getContext(), i == 0 ? sim::CaptureKind::Context
                                           : sim::CaptureKind::Formal))}));
    auto fn = sim::SimFuncOp::create(builder, loc, name,
                                     builder.getFunctionType(inputs, {}), kind,
                                     attrs, args);
    SymbolTable::setSymbolVisibility(fn, SymbolTable::Visibility::Private);
    sim::mark<sim::metadata::Lowered>(fn);
    return fn;
  }
  Descriptor storage(Location loc, StringRef name, Type type) {
    builder.setInsertionPointToStart(&design.getBody().front());
    Descriptor result{nextStorage++, type};
    sim::SimStorageDeclOp::create(
        builder, loc, result.id, uint64_t{0}, type, sim::Lifetime::Design,
        builder.getStringAttr(name), builder.getStringAttr(name),
        schedule::ComputeObservabilityKindAttr{}, sim::VPITypeSemanticsAttr{});
    return result;
  }
  LogicalResult watch(sim::SimFuncOp fn, Descriptor descriptor) {
    builder.setInsertionPointToStart(&fn.getBody().front());
    Value reference =
        handle(builder, fn.getLoc(), fn.getArgument(0), descriptor);
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(op))
        waits.push_back(op);
    });
    for (Operation *op : waits) {
      if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op)) {
        SmallVector<Value> values(any.getWatched());
        values.push_back(reference);
        llvm::append_range(values, any.getContinuationOperands());
        SmallVector<int32_t> edges(any.getEdges());
        edges.push_back(0);
        any.getValuesMutable().assign(values);
        any.setEdgesAttr(builder.getDenseI32ArrayAttr(edges));
      } else {
        auto change = cast<sim::SimSuspendChangeOp>(op);
        builder.setInsertionPoint(op);
        SmallVector<Value> values{change.getWatched(), reference};
        llvm::append_range(values, change.getContinuationOperands());
        sim::SimSuspendAnyOp::create(
            builder, op->getLoc(), values, builder.getDenseI32ArrayAttr({0, 0}),
            change.getSiteAttr(), change.getResumeRegionAttr(),
            change.getContinuation());
        op->erase();
      }
    }
    return success();
  }
  LogicalResult isolation(sim::SimFuncOp fn, upf::UPFDomainOp domain,
                          Descriptor control) {
    // IEEE 1801-2018 9.8: an unknown isolation control corrupts the output,
    // even when data equals the clamp. Explicit known-level tests avoid the
    // equal-bit merging that an ordinary SystemVerilog conditional would use.
    if (failed(watch(fn, control)))
      return failure();
    SmallVector<Operation *> writes;
    fn.walk([&](Operation *op) {
      if (isa<sim::SimDriverDriveOp, sim::SimRefStoreOp, sim::SimNetWriteOp>(
              op))
        writes.push_back(op);
    });
    if (writes.empty())
      return fn.emitError(
          "UPF isolation requires an explicit scalar output connection");
    for (Operation *op : writes) {
      Value value;
      if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
        value = drive.getValue();
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
        value = write.getValue();
      if (auto write = dyn_cast<sim::SimNetWriteOp>(op))
        value = write.getValue();
      Type outputType = value.getType();
      auto logic = dyn_cast_or_null<sim::LogicType>(
          sim::getPackedScalarType(outputType));
      if (!logic || !supportedState(outputType))
        return op->emitError(
            "initial UPF isolation requires four-state packed outputs");
      builder.setInsertionPoint(op);
      value = flatten(builder, op->getLoc(), value);
      Value input =
          load(builder, op->getLoc(),
               handle(builder, op->getLoc(), fn.getArgument(0), control));
      Value active =
          equalsLevel(builder, op->getLoc(), input, domain.getIsolationHigh());
      Value inactive =
          equalsLevel(builder, op->getLoc(), input, !domain.getIsolationHigh());
      Value data = logicSelect(builder, op->getLoc(), inactive, value,
                               corrupt(builder, op->getLoc(), logic));
      Value result = logicSelect(
          builder, op->getLoc(), active,
          logicConstant(builder, op->getLoc(), logic, domain.getClamp() != 0),
          data);
      if (result.getType() != outputType)
        result = sim::SimPackedUnflattenOp::create(builder, op->getLoc(),
                                                   outputType, result);
      if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
        drive.getValueMutable().assign(result);
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
        write.getValueMutable().assign(result);
      if (auto write = dyn_cast<sim::SimNetWriteOp>(op))
        write.getValueMutable().assign(result);
    }
    return success();
  }
  LogicalResult gate(sim::SimFuncOp fn, Descriptor control, bool high) {
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (op->getName().getStringRef().starts_with("simulation.suspend."))
        waits.push_back(op);
    });
    if (waits.size() != 1)
      return fn.emitError("initial UPF domain requires one repeating event "
                          "control per process");
    Operation *wait = waits.front();
    if (!isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp,
             sim::SimSuspendEdgeOp, sim::SimSuspendEdgeIffOp>(wait))
      return wait->emitError(
          "blocking timing inside a switchable domain is not implemented");
    // IEEE 1801-2018 9.5.3/9.6.2 suppress the complete activation, including
    // branches preceding the wait. The wait's continuation is the activation
    // entry for both explicit event controls and implicit combinational loops.
    Block *skip;
    Block *gate = wait->getSuccessor(0);
    bool leadingWait = wait->hasAttr("schedule.repeating_always_wait") ||
                       wait->hasAttr("schedule.top_level_wildcard_wait");
    if (leadingWait) {
      skip = wait->getBlock();
    } else {
      if (fn.getEntryKind() != sim::EntryKind::AlwaysComb &&
          fn.getEntryKind() != sim::EntryKind::Continuous)
        return fn.emitError("UPF requires a top-level repeating event control");
      Block *last = wait->getBlock();
      skip = last->splitBlock(Block::iterator(wait));
      builder.setInsertionPointToEnd(last);
      cf::BranchOp::create(builder, fn.getLoc(), skip);
    }
    if (skip->getNumArguments() != 0 || gate == &fn.getBody().front())
      return fn.emitError("initial UPF process requires an explicit repeating "
                          "sensitivity loop");
    Block *body = gate->splitBlock(gate->begin());
    builder.setInsertionPointToEnd(gate);
    Value on = powerOn(builder, fn.getLoc(), fn.getArgument(0), control, high);
    cf::CondBranchOp::create(builder, fn.getLoc(), on, body, ValueRange{}, skip,
                             ValueRange{});
    // IEEE 1801-2018 9.6.7: restoration reevaluates combinational/level logic,
    // but must not invent an edge activation for edge-sensitive state.
    bool edgeSensitive =
        isa<sim::SimSuspendEdgeOp, sim::SimSuspendEdgeIffOp>(wait);
    if (auto any = dyn_cast<sim::SimSuspendAnyOp>(wait)) {
      bool level = llvm::is_contained(any.getEdges(), 0);
      bool edge =
          llvm::any_of(any.getEdges(), [](int32_t kind) { return kind != 0; });
      if (edge && level)
        return fn.emitError("mixed level/edge sensitivity in a switchable "
                            "domain is not implemented");
      edgeSensitive = edge;
    }
    return edgeSensitive ? success() : watch(fn, control);
  }
  void nba(sim::SimNBAEnqueueOp enqueue, Descriptor control, bool high,
           Descriptor epoch) {
    // IEEE 1801-2018 9.5.3: events queued before CORRUPT have no effect.
    // Capturing the epoch also prevents an OFF/ON cycle from reviving an old
    // delayed event merely because the domain is NORMAL again at commit time.
    sim::SimFuncOp caller = enqueue->getParentOfType<sim::SimFuncOp>();
    Location loc = enqueue.getLoc();
    Type contextType = sim::ContextType::get(builder.getContext()),
         delayType = sim::TimeType::get(builder.getContext());
    auto commit = function(loc, (Twine("__upf_nba_") + Twine(nextUnit)).str(),
                           {contextType, enqueue.getDestination().getType(),
                            enqueue.getValue().getType(), builder.getI64Type(),
                            delayType},
                           sim::EntryKind::Fork);
    Block &entry = commit.getBody().front();
    Block *check = new Block, *publish = new Block, *done = new Block;
    commit.getBody().push_back(check);
    commit.getBody().push_back(publish);
    commit.getBody().push_back(done);
    builder.setInsertionPointToEnd(&entry);
    sim::SimSuspendDelayOp::create(builder, loc, entry.getArgument(4),
                                   schedule::TimingSiteAttr{}, ValueRange{},
                                   schedule::ContinuationSiteAttr{},
                                   sim::EventRegionAttr{}, check);
    builder.setInsertionPointToEnd(check);
    Value current =
        load(builder, loc, handle(builder, loc, entry.getArgument(0), epoch));
    Value same = arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::eq,
                                       current, entry.getArgument(3));
    Value on = powerOn(builder, loc, entry.getArgument(0), control, high);
    Value valid = arith::AndIOp::create(builder, loc, same, on);
    cf::CondBranchOp::create(builder, loc, valid, publish, done);
    builder.setInsertionPointToEnd(publish);
    Value zeroDelay =
        sim::SimTimeConstantOp::create(builder, loc, delayType, uint64_t{0});
    sim::SimNBAEnqueueOp::create(builder, loc, entry.getArgument(2),
                                 entry.getArgument(1), zeroDelay,
                                 schedule::NBASiteAttr{}, IntegerAttr{});
    cf::BranchOp::create(builder, loc, done);
    builder.setInsertionPointToEnd(done);
    sim::SimReturnOp::create(builder, loc, ValueRange{});
    builder.setInsertionPoint(enqueue);
    Value context = caller.getArgument(0);
    Value snapshot = load(builder, loc, handle(builder, loc, context, epoch));
    Value delay = enqueue.getDelay();
    if (!delay)
      delay =
          sim::SimTimeConstantOp::create(builder, loc, delayType, uint64_t{0});
    sim::SimSpawnOp::create(builder, loc, commit.getSymNameAttr(),
                            ValueRange{context, enqueue.getDestination(),
                                       enqueue.getValue(), snapshot, delay},
                            ArrayAttr{}, ArrayAttr{});
    enqueue.erase();
  }
  LogicalResult apply(upf::UPFDomainOp domain) {
    if (!root)
      return domain.emitError("UPF needs an executable design root");
    auto controlFound = descriptors.find(domain.getControl());
    if (controlFound == descriptors.end())
      return domain.emitError(
          "power control is absent from the simulation design");
    Descriptor control = controlFound->second;
    if (contains(domain, domain.getControl()))
      return domain.emitError(
          "power control must be outside the switchable domain");
    // IEEE 1801-2018 6.45 and 8.3.3(g),(j) select power-domain boundaries,
    // not every nested module boundary. Until full boundary selection exists,
    // accept only leaf module elements rather than clamping internal wires.
    for (auto scope : design.getOps<sim::SimScopeDeclOp>()) {
      auto path = scope.getHierarchicalName();
      if (!path || !scope.getDefinitionName() || !contains(domain, *path))
        continue;
      bool descendant = llvm::any_of(domain.getElements(), [&](Attribute attr) {
        StringRef element = cast<StringAttr>(attr).getValue();
        return path->starts_with(element) &&
               path->drop_front(element.size()).starts_with('.');
      });
      if (descendant)
        return domain.emitError(
            "initial UPF domain elements must be leaf module instances");
    }
    SmallVector<sim::SimFuncOp> processes, outputs;
    for (auto fn : design.getOps<sim::SimFuncOp>()) {
      if (!fn.getCodeUnitId() ||
          !contains(domain, unitPaths.lookup(*fn.getCodeUnitId())))
        continue;
      switch (fn.getEntryKind()) {
      case sim::EntryKind::Always:
      case sim::EntryKind::AlwaysFF:
      case sim::EntryKind::AlwaysComb:
      case sim::EntryKind::Continuous:
        processes.push_back(fn);
        break;
      case sim::EntryKind::PortOutput:
        outputs.push_back(fn);
        break;
      case sim::EntryKind::PortInput:
      case sim::EntryKind::PortInitialize:
      case sim::EntryKind::Observer:
        break;
      case sim::EntryKind::Initial:
        break; // IEEE 1801 9.2.1: model initialization is unaffected.
      case sim::EntryKind::Function:
        if (auto path = sim::get<sim::metadata::HierarchicalName>(fn))
          if (descriptors.count(path.getValue()))
            break;
        return fn.emitError(
            "user subroutines inside a switchable domain are not implemented");
      default:
        return fn.emitError(
            "initial UPF slice supports event-controlled RTL and combinational "
            "processes; this code-unit kind is not implemented");
      }
    }
    llvm::DenseSet<uint64_t> inputStorage, inputNets;
    for (auto port : design.getOps<sim::SimPortDeclOp>()) {
      if (!contains(domain, port.getHierarchicalName()))
        continue;
      if (port.getDirection() == sim::PortDirection::InOut)
        return port.emitError(
            "inout ports in a switchable domain are not implemented");
      if (port.getDirection() == sim::PortDirection::Input)
        (port.getSourceIsNet() ? inputNets : inputStorage)
            .insert(port.getSourceId());
    }
    SmallVector<Descriptor> targets;
    llvm::DenseSet<uint64_t> continuouslyDriven;
    for (auto process : processes) {
      process.walk([&](sim::SimRefStoreOp write) {
        if (process.getEntryKind() != sim::EntryKind::Continuous &&
            !sim::has<sim::metadata::ContinuousStore>(write))
          return;
        Value root = write.getReference();
        while (auto slice = root.getDefiningOp<sim::SimRefExtractOp>())
          root = slice.getInput();
        if (auto storage = root.getDefiningOp<sim::SimContextStorageOp>())
          continuouslyDriven.insert(storage.getId());
        if (auto argument = dyn_cast<BlockArgument>(root))
          if (argument.getOwner() == &process.getBody().front())
            if (auto id = process.getArgAttrOfType<IntegerAttr>(
                    argument.getArgNumber(),
                    sim::metadata::DescriptorId::getNameStr()))
              continuouslyDriven.insert(id.getInt());
      });
    }
    for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
      if (!decl.getHierarchicalName() ||
          !contains(domain, *decl.getHierarchicalName()) ||
          inputStorage.contains(decl.getId()))
        continue;
      if (!supportedState(decl.getType()))
        return decl.emitError(
            "initial UPF corruption supports packed integral state");
      targets.push_back({decl.getId(), decl.getType()});
    }
    for (auto decl : design.getOps<sim::SimDriverDeclOp>()) {
      if (!decl.getHierarchicalName() ||
          !contains(domain, *decl.getHierarchicalName()) ||
          inputNets.contains(decl.getNetId()))
        continue;
      if (!supportedState(decl.getType()) ||
          !isa_and_nonnull<sim::LogicType>(
              sim::getPackedScalarType(decl.getType())))
        return decl.emitError(
            "initial UPF corruption supports packed logic drivers");
      targets.push_back({decl.getId(), decl.getType(), false, true});
    }
    if (targets.empty())
      return domain.emitError(
          "switchable domain has no supported state or drivers");
    if (auto isoName = domain.getIsolationControl()) {
      auto found = descriptors.find(*isoName);
      if (found == descriptors.end() || contains(domain, *isoName))
        return domain.emitError("parent isolation requires a control outside "
                                "the switchable domain");
      if (outputs.empty())
        return domain.emitError(
            "isolation has no explicit output boundary to apply to");
      for (auto output : outputs)
        if (failed(isolation(output, domain, found->second)))
          return failure();
    }
    Location loc = domain.getLoc();
    std::string prefix = "__upf_" + domain.getSymName().str();
    Descriptor epoch = storage(loc, prefix + ".epoch", builder.getI64Type());
    Descriptor previous =
        storage(loc, prefix + ".previous", builder.getI1Type());
    for (auto process : processes) {
      WalkResult supported = process.walk([&](Operation *op) {
        StringRef name = op->getName().getStringRef();
        // IEEE 1801-2018 9.5.3 invalidates old delayed driver events too.
        // Those cancellation queues are outside the initial packed-NBA slice.
        if (name.contains("drive_inertial") ||
            name.contains("drive_delayed_net") ||
            name == "simulation.ref.store_inertial_path" ||
            isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
                sim::SimReleaseOverrideOp>(op)) {
          op->emitError("delayed drivers and force/release inside a switchable "
                        "domain are not implemented");
          return WalkResult::interrupt();
        }
        if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(op))
          if (enqueue.getClockingOutputAttr()) {
            // IEEE 1801-2018 9.5.2 preserves HDL clocking semantics in NORMAL.
            enqueue.emitError("clocking-output NBAs in a switchable domain are "
                              "not implemented");
            return WalkResult::interrupt();
          }
        if (auto spawn = dyn_cast<sim::SimSpawnOp>(op)) {
          auto target = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
              spawn, spawn.getCalleeAttr());
          bool clockingOutput = false;
          if (target)
            target.walk([&](sim::SimNBAEnqueueOp enqueue) {
              clockingOutput |= bool(enqueue.getClockingOutputAttr());
            });
          // Clocking drives are outlined before this pass; their helper's
          // synthetic hierarchy is not a power-domain membership proof.
          if (clockingOutput)
            spawn.emitError("clocking-output NBAs in a switchable domain are "
                            "not implemented");
          else
            spawn.emitError("forked or outlined work inside a switchable "
                            "domain is not implemented");
          return WalkResult::interrupt();
        }
        if (isa<sim::SimCallOp>(op)) {
          op->emitError("user subroutines inside a switchable domain are not "
                        "implemented");
          return WalkResult::interrupt();
        }
        return WalkResult::advance();
      });
      if (supported.wasInterrupted())
        return failure();
      SmallVector<sim::SimNBAEnqueueOp> enqueues;
      process.walk([&](sim::SimNBAEnqueueOp op) { enqueues.push_back(op); });
      for (auto enqueue : enqueues)
        nba(enqueue, control, domain.getOnHigh(), epoch);
      if (failed(gate(process, control, domain.getOnHigh())))
        return failure();
    }
    auto monitor = function(loc, prefix + ".monitor",
                            {sim::ContextType::get(builder.getContext())},
                            sim::EntryKind::Always);
    sim::mark<sim::metadata::PowerMonitor>(monitor);
    Block &entry = monitor.getBody().front();
    Block *loop = new Block, *loss = new Block, *wait = new Block;
    monitor.getBody().push_back(loop);
    monitor.getBody().push_back(loss);
    monitor.getBody().push_back(wait);
    builder.setInsertionPointToEnd(&entry);
    Value context = entry.getArgument(0),
          epochRef = handle(builder, loc, context, epoch);
    Value previousRef = handle(builder, loc, context, previous),
          watched = handle(builder, loc, context, control);
    cf::BranchOp::create(builder, loc, loop);
    builder.setInsertionPointToEnd(loop);
    Value on = powerOn(builder, loc, context, control, domain.getOnHigh());
    Value wasOn = load(builder, loc, previousRef);
    store(builder, loc, previousRef, on);
    Value off = arith::XOrIOp::create(
        builder, loc, on, arith::ConstantIntOp::create(builder, loc, 1, 1));
    Value falling = arith::AndIOp::create(builder, loc, wasOn, off);
    cf::CondBranchOp::create(builder, loc, falling, loss, wait);
    builder.setInsertionPointToEnd(loss);
    Value oldEpoch = load(builder, loc, epochRef);
    Value nextEpoch = arith::AddIOp::create(
        builder, loc, oldEpoch,
        arith::ConstantIntOp::create(builder, loc, 1, 64));
    store(builder, loc, epochRef, nextEpoch);
    for (Descriptor target : targets) {
      // IEEE 1801-2018 9.5.1/9.6.2: corruption uses the HDL type's default
      // initial value, independently of explicit declaration initializers.
      Value reference = handle(builder, loc, context, target);
      if (!target.driver) {
        uint64_t width = *sim::getPackedWidth(target.type);
        sim::SimPowerCancelNBAOp::create(builder, loc, context, reference,
                                         width);
      }
      store(builder, loc, reference, corrupt(builder, loc, target.type));
      if (!target.driver && continuouslyDriven.contains(target.id))
        sim::mark<sim::metadata::ContinuousStore>(
            &*std::prev(builder.getInsertionPoint()));
    }
    cf::BranchOp::create(builder, loc, wait);
    builder.setInsertionPointToEnd(wait);
    sim::SimSuspendChangeOp::create(builder, loc, watched, ValueRange{},
                                    schedule::ContinuationSiteAttr{},
                                    sim::EventRegionAttr{}, loop);
    Operation *firstSpawn = nullptr;
    for (Operation &op : root.getBody().front())
      if (isa<sim::SimSpawnOp>(op)) {
        firstSpawn = &op;
        break;
      }
    builder.setInsertionPoint(
        firstSpawn ? firstSpawn : root.getBody().front().getTerminator());
    Value rootContext = root.getArgument(0);
    store(builder, loc, handle(builder, loc, rootContext, epoch),
          arith::ConstantIntOp::create(builder, loc, 0, 64));
    store(builder, loc, handle(builder, loc, rootContext, previous),
          arith::ConstantIntOp::create(builder, loc, 1, 1));
    sim::SimSpawnOp::create(builder, loc, monitor.getSymNameAttr(),
                            ValueRange{rootContext}, ArrayAttr{}, ArrayAttr{});
    domain.erase();
    return success();
  }
};
struct ElaborateUPFPass
    : PassWrapper<ElaborateUPFPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ElaborateUPFPass)
  StringRef getArgument() const final { return "elaborate-upf"; }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<sim::TalosSimulationDialect, arith::ArithDialect,
                    cf::ControlFlowDialect>();
  }
  void runOnOperation() override {
    SmallVector<upf::UPFDomainOp> domains(
        getOperation().getOps<upf::UPFDomainOp>());
    if (domains.empty())
      return;
    // IEEE 1801-2018 6.20 assigns an instance to exactly one effective extent.
    // Until nested-domain extent partitioning exists, require disjoint roots;
    // validate the entire inventory before adding any guards or corruption.
    for (auto [index, domain] : llvm::enumerate(domains))
      for (auto other : ArrayRef(domains).take_front(index))
        for (Attribute element : domain.getElements())
          for (Attribute otherElement : other.getElements()) {
            StringRef path = cast<StringAttr>(element).getValue();
            StringRef otherPath = cast<StringAttr>(otherElement).getValue();
            auto within = [](StringRef child, StringRef parent) {
              return child == parent ||
                     (child.starts_with(parent) &&
                      child.drop_front(parent.size()).starts_with('.'));
            };
            if (within(path, otherPath) || within(otherPath, path)) {
              auto diagnostic = domain.emitError();
              if (path == otherPath)
                diagnostic << "design instance is selected by multiple "
                              "switchable domains: "
                           << path;
              else
                diagnostic << "nested switchable domains are not implemented: "
                           << domain.getSymName() << " and "
                           << other.getSymName();
              signalPassFailure();
              return;
            }
          }
    auto designs = getOperation().getOps<sim::SimDesignOp>();
    if (!llvm::hasSingleElement(designs)) {
      domains.front().emitError("UPF requires exactly one simulation design");
      signalPassFailure();
      return;
    }
    Lowering lowering(*designs.begin());
    for (auto domain : domains)
      if (failed(lowering.apply(domain))) {
        signalPassFailure();
        return;
      }
  }
};
} // namespace
std::unique_ptr<Pass> createElaborateUPFPass() {
  return std::make_unique<ElaborateUPFPass>();
}
} // namespace talos
