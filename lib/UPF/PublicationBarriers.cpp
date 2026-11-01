//===- PublicationBarriers.cpp - Event-time snapshot boundaries ---------===//

#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationResources.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

#include <optional>

using namespace mlir;

namespace talos {
namespace {

bool needsSnapshots(ModuleOp module) {
  if (sim::has<sim::metadata::SnapshotPublications>(module))
    return true;
  bool needed = false;
  module.walk([&](sim::SimEventSnapshotRegisterOp) { needed = true; });
  module.walk([&](upf::UPFDomainOp domain) {
    if (auto strategies = domain.getRetentionsAttr())
      for (auto attribute : strategies) {
        auto retention = cast<upf::RetentionAttr>(attribute);
        // IEEE 1801-2018 6.50/9.7.3: either control selects balloon intent.
        needed |= !retention.getNoRetention() &&
                  (retention.getSave() || retention.getRestore());
      }
  });
  return needed;
}

// An empty Value inside the optional means an operation publishes without an
// ordinary ref target. No optional means it does not publish synchronously.
std::optional<Value> publicationTarget(Operation *operation) {
  if (auto store = dyn_cast<sim::SimRefStoreOp>(operation))
    return store.getReference();
  if (auto copy = dyn_cast<sim::SimRefCopyOp>(operation))
    return copy.getDestination();
  if (auto store = dyn_cast<sim::SimArgumentRefStoreOp>(operation))
    return store.getReference();
  if (auto store = dyn_cast<sim::SimRefStoreInertialPathOp>(operation))
    return store.getNonblocking() ? std::nullopt
                                  : std::optional<Value>(store.getReference());
  if (auto override = dyn_cast<sim::SimOverrideOp>(operation))
    return override.getTarget();
  if (auto override = dyn_cast<sim::SimDynamicOverrideOp>(operation))
    return override.getTarget();
  if (auto release = dyn_cast<sim::SimReleaseOverrideOp>(operation))
    return release.getTarget();
  // Inertial/delayed operations may resolve immediately when delay is zero.
  // One compiler operation is one boundary; runtime-owned maturity and net
  // alias groups require their separate complete-publication protocol.
  if (isa<sim::SimNetWriteOp, sim::SimDriverDriveOp,
          sim::SimDriverDriveChangedOp, sim::SimDriverDriveInertialOp,
          sim::SimDriverDriveInertialPathOp,
          sim::SimDriverDriveInertialStrengthPairOp,
          sim::SimDriverDriveInertialPathStrengthPairOp,
          sim::SimDriverDriveDelayedNetOp, sim::SimPassSwitchControlOp,
          sim::SimPassSwitchControlDelayedOp, sim::SimMosDriveDelayedOp,
          sim::SimSupplyControlOp>(operation))
    return Value{};
  return std::nullopt;
}

struct ReferenceRoots {
  DenseMap<uint64_t, sim::Lifetime> storageLifetimes;

  explicit ReferenceRoots(sim::SimDesignOp design) {
    for (auto storage : design.getOps<sim::SimStorageDeclOp>())
      storageLifetimes[storage.getId()] = storage.getLifetime();
  }

  bool isAutomatic(Value reference) const {
    if (!isa<sim::RefType, sim::ArgumentRefType>(reference.getType()))
      return false;
    SmallVector<Value> pending{reference};
    DenseSet<Value> seen;
    bool foundRoot = false;
    while (!pending.empty()) {
      Value value = pending.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      if (value.getDefiningOp<sim::SimRefAllocOp>()) {
        foundRoot = true;
        continue;
      }
      if (auto storage = value.getDefiningOp<sim::SimContextStorageOp>()) {
        auto found = storageLifetimes.find(storage.getId());
        if (found == storageLifetimes.end() ||
            found->second != sim::Lifetime::Automatic)
          return false;
        foundRoot = true;
        continue;
      }
      if (auto erased = value.getDefiningOp<sim::SimArgumentRefFromRefOp>()) {
        pending.push_back(erased.getInput());
        continue;
      }
      if (auto retyped = value.getDefiningOp<sim::SimArgumentRefRetypeOp>()) {
        pending.push_back(retyped.getInput());
        continue;
      }
      if (auto view =
              dyn_cast_or_null<ViewLikeOpInterface>(value.getDefiningOp())) {
        pending.push_back(view.getViewSource());
        continue;
      }
      auto argument = dyn_cast<BlockArgument>(value);
      if (!argument || argument.getOwner()->hasNoPredecessors())
        return false;
      for (Block *predecessor : argument.getOwner()->getPredecessors()) {
        auto branch = dyn_cast<BranchOpInterface>(predecessor->getTerminator());
        if (!branch)
          return false;
        for (unsigned index = 0; index != branch->getNumSuccessors(); ++index) {
          if (branch->getSuccessor(index) != argument.getOwner())
            continue;
          SuccessorOperands operands = branch.getSuccessorOperands(index);
          unsigned lane = argument.getArgNumber();
          if (lane >= operands.size() || operands.isOperandProduced(lane))
            return false;
          pending.push_back(operands[lane]);
        }
      }
    }
    // A cycle without a proven allocation/declaration cannot establish a
    // local lifetime. Mixed local/persistent and opaque formals publish.
    return foundRoot;
  }
};

bool deferredOrInspected(Operation *operation) {
  return isa<sim::SimCallOp, sim::SimTaskCallOp, sim::SimSpawnOp,
             sim::SimClassDirectCallOp, sim::SimClassVirtualCallOp,
             sim::SimClassVirtualTaskCallOp, sim::SimRefAllocOp,
             sim::SimNBAEnqueueOp, sim::SimManagedNBAEnqueueOp,
             sim::SimManagedNBAEnqueueMaskedOp,
             sim::SimReferencePathNBAEnqueueOp, sim::SimPowerNBAOp,
             sim::SimPowerNBAViewOp, sim::SimEventSnapshotRegisterOp,
             sim::SimEventSnapshotFlushOp, sim::SimRefStoreInertialPathOp>(
      operation);
}

struct PrepareUPFSnapshotPublicationsPass
    : PassWrapper<PrepareUPFSnapshotPublicationsPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(
      PrepareUPFSnapshotPublicationsPass)

  StringRef getArgument() const final {
    return "prepare-upf-snapshot-publications";
  }
  StringRef getDescription() const final {
    return "Preserve synchronous publications for IEEE 1801 event-time "
           "snapshots";
  }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<sim::TalosSimulationDialect, upf::UPFDialect>();
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (!needsSnapshots(module))
      return markAllAnalysesPreserved();
    // Preflight before changing IR: serialized executable images and graph
    // summaries cannot be repaired by adding a boundary afterward.
    auto designs = module.getOps<sim::SimDesignOp>();
    if (!llvm::hasSingleElement(designs)) {
      module.emitError(
          "snapshot publication preparation requires one simulation design");
      return signalPassFailure();
    }
    auto design = *designs.begin();
    if (design.getComputeGraphAttr() ||
        native::has<native::PartitionManifest>(design) ||
        native::has<native::PartitionManifests>(module) ||
        native::has<native::PhysicalPartitionManifest>(module) ||
        runtime::has<runtime::BytecodeImage>(module) ||
        runtime::has<runtime::LLVMPrepared>(module) ||
        runtime::has<runtime::Materialized>(module)) {
      module.emitError("snapshot publications must be prepared before "
                       "scheduling and encoding");
      return signalPassFailure();
    }
    ReferenceRoots roots(design);
    SymbolTableCollection symbols;
    SmallVector<sim::SimFuncOp> functions(design.getOps<sim::SimFuncOp>());
    SmallVector<Operation *> batches;
    DenseMap<Operation *, SmallVector<Operation *>> publishers;
    DenseMap<Operation *, SmallVector<sim::SimFuncOp>> callees;
    DenseMap<Operation *, Operation *> opaqueCalls;
    bool invalid = false;
    for (auto function : functions) {
      if (runtime::has<runtime::BytecodeFunction>(function) ||
          native::has<native::Frame>(function)) {
        function.emitError(
            "snapshot publications must precede function encoding");
        invalid = true;
      }
      function.walk([&](Operation *operation) {
        if (operation == function)
          return;
        if (auto call = dyn_cast<sim::SimDPICallOp>(operation)) {
          if (call.getIsContext()) {
            call.emitError("snapshot publication boundaries for context DPI "
                           "imports are not implemented");
            invalid = true;
          }
        }
        if (isa<sim::SimPublicationBatchBeginOp, sim::SimPublicationBatchEndOp>(
                operation))
          batches.push_back(operation);
        if (auto target = publicationTarget(operation)) {
          if (!*target || !roots.isAutomatic(*target))
            publishers[function].push_back(operation);
          return;
        }
        if (isa<sim::SimEventSnapshotFlushOp>(operation))
          opaqueCalls.try_emplace(function, operation);
        if (isa<sim::SimClassVirtualCallOp, sim::SimClassVirtualTaskCallOp>(
                operation))
          opaqueCalls.try_emplace(function, operation);
        if (isa<sim::SimCallOp, sim::SimTaskCallOp, sim::SimSpawnOp,
                sim::SimClassDirectCallOp>(operation)) {
          auto symbol = operation->getAttrOfType<FlatSymbolRefAttr>("callee");
          auto callee = symbol
                            ? symbols.lookupNearestSymbolFrom<sim::SimFuncOp>(
                                  operation, symbol)
                            : sim::SimFuncOp{};
          if (!callee || callee.isExternal()) {
            operation->emitError(
                "snapshot publications require defined compiled call targets");
            invalid = true;
          } else {
            callees[function].push_back(callee);
          }
        } else if (isa<CallOpInterface>(operation)) {
          operation->emitError(
              "snapshot publications require defined compiled call targets");
          invalid = true;
          return;
        }
        if (deferredOrInspected(operation))
          return;
        if (auto effects = dyn_cast<MemoryEffectOpInterface>(operation)) {
          SmallVector<MemoryEffects::EffectInstance> instances;
          effects.getEffects(instances);
          if (llvm::any_of(instances, [](const auto &effect) {
                return isa<MemoryEffects::Write>(effect.getEffect()) &&
                       (effect.getResource() == sim::StorageResource::get() ||
                        effect.getResource() == sim::NetResource::get() ||
                        effect.getResource() ==
                            SideEffects::DefaultResource::get());
              })) {
            operation->emitError(
                "unsupported synchronous snapshot publication");
            invalid = true;
          }
        } else if (!isMemoryEffectFree(operation) &&
                   !operation->hasTrait<OpTrait::HasRecursiveMemoryEffects>()) {
          // Unknown effects cannot prove absence of an immediate publication.
          // Recursive region operations are inspected by the enclosing walk.
          operation->emitError(
              "snapshot publications require classified memory effects");
          invalid = true;
        }
      });
    }
    // IEEE 1801-2018 6.50: callbacks sample before target commit. A flush
    // reached from an observer would violate the runtime's read-only scope.
    // Check complete direct closures before instrumenting any helper body.
    for (auto function : functions) {
      if (function.getEntryKind() != sim::EntryKind::Observer)
        continue;
      SmallVector<sim::SimFuncOp> pending{function};
      DenseSet<Operation *> seen;
      while (!pending.empty()) {
        auto callee = pending.pop_back_val();
        if (!seen.insert(callee).second)
          continue;
        Operation *bad = opaqueCalls.lookup(callee);
        auto found = publishers.find(callee);
        if (found != publishers.end() && !found->second.empty())
          bad = found->second.front();
        if (bad) {
          auto diagnostic =
              bad->emitError("snapshot callbacks require an inspectable "
                             "closure without persistent publications");
          diagnostic.attachNote(function.getLoc())
              << "observer callback is declared here";
          invalid = true;
          break;
        }
        llvm::append_range(pending, callees[callee]);
      }
    }
    if (invalid)
      return signalPassFailure();
    bool changed = !sim::has<sim::metadata::SnapshotPublications>(module);
    sim::mark<sim::metadata::SnapshotPublications>(module);
    // Batches are optional merging hints (1800-2023 4.7/9.4.2). Exact
    // observers already disable merging; removing both markers permits each
    // source write's explicit flush without an active runtime batch scope.
    for (auto *batch : batches) {
      batch->erase();
      changed = true;
    }
    OpBuilder builder(module.getContext());
    for (auto function : functions) {
      if (function.isExternal())
        continue;
      Value context = function.getBody().front().getArgument(0);
      for (auto *publisher : publishers[function]) {
        auto next = dyn_cast_or_null<sim::SimEventSnapshotFlushOp>(
            publisher->getNextNode());
        if (next && next.getContext() == context)
          continue;
        builder.setInsertionPointAfter(publisher);
        sim::SimEventSnapshotFlushOp::create(builder, publisher->getLoc(),
                                             context);
        changed = true;
      }
    }
    if (!changed)
      markAllAnalysesPreserved();
  }
};
} // namespace

std::unique_ptr<Pass> createPrepareUPFSnapshotPublicationsPass() {
  return std::make_unique<PrepareUPFSnapshotPublicationsPass>();
}
} // namespace talos
