//===- ActivationRegionAnalysis.h - Activation regions ---------*- C++ -*-===//
#ifndef TALOS_ANALYSIS_ACTIVATIONREGIONANALYSIS_H
#define TALOS_ANALYSIS_ACTIVATIONREGIONANALYSIS_H

#include "mlir/IR/OwningOpRef.h"
#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace talos::analysis {

/// Read-only CFG view of one change-sensitive activation. Initial and resumed
/// activations must have equivalent CFGs, and remaining cycles need bounded-loop
/// termination certificates. Loops remain in the CFG rather than being unrolled.
///
/// Chain blocks dominate the suspension and belong to no CFG cycle. Each of
/// their operations is a scheduling unit. The branch and intervening blocks
/// between chain blocks form a region unit whose results are the next block's
/// arguments.
///
/// Memory facts include intermediate writes. Clients separately establish
/// activation eligibility, publication ordering, sensitivity, and observer
/// legality before transforming the view.
class ActivationRegionAnalysis {
public:
  enum class FailureReason {
    None,
    ActivationShape,
    InitialResumeEquivalence,
    Termination,
    MemoryEffects,
    UnmappedMemoryAccess,
  };
  enum class TracePhase { Initial, Resume };
  /// Clients materializing the CFG view may prepare dispatch edges.
  /// Summary-only clients can retain the existing canonical CFG policy.
  enum class ControlFlowPreparation { Canonical, ThreadDispatch };
  using Ranges = ActivationMemoryAnalysis::Ranges;
  struct Node {
    /// An operation unit, or the branch that enters a region unit.
    mlir::Operation *operation;
    /// Region units only: the blocks strictly inside the region, in CFG order,
    /// and the chain block entered when the region exits.
    llvm::SmallVector<mlir::Block *> blocks;
    mlir::Block *join = nullptr;
    Ranges reads, writes;
    bool isRegion() const { return join != nullptr; }
    /// Visit every operation of the unit, including a region's entry branch.
    void walk(llvm::function_ref<void(mlir::Operation *)> callback) const;
  };
  /// Optional diagnostic views; the callback must not retain their IR.
  using Trace = llvm::function_ref<void(TracePhase, mlir::Operation *)>;
  ActivationRegionAnalysis(
      sim::SimFuncOp function, const HandleDataflowAnalysis &handles,
      Trace trace = {},
      ActivationMemoryAnalysis::DependencyMode mode =
          ActivationMemoryAnalysis::DependencyMode::Accesses,
      ControlFlowPreparation control = ControlFlowPreparation::Canonical);
  bool isValid() const { return reason == FailureReason::None; }
  FailureReason getFailureReason() const { return reason; }
  llvm::ArrayRef<Node> getNodes() const { return nodes; }
  /// The unit containing an operation of the CFG view, or nullptr.
  const Node *getNode(mlir::Operation *operation) const;
  /// The unit defining a value of the CFG view, or nullptr for an entry
  /// argument. A region unit defines its join block's arguments.
  const Node *getDefiningNode(mlir::Value value) const;
  /// The initial activation as a closed function: its suspension is replaced
  /// by a return. Memory facts refer to this view's operations.
  sim::SimFuncOp getActivationFunction() const { return view.get(); }
  const ActivationMemoryAnalysis &getMemory() const { return memory; }
  mlir::Operation *getSuspension() const { return suspension; }

private:
  ActivationMemoryAnalysis memory;
  mlir::OwningOpRef<sim::SimFuncOp> view;
  llvm::SmallVector<Node> nodes;
  llvm::DenseMap<mlir::Operation *, unsigned> nodeIndices;
  llvm::DenseMap<mlir::Block *, unsigned> argumentNodes;
  mlir::Operation *suspension = nullptr;
  FailureReason reason = FailureReason::ActivationShape;
};

llvm::StringRef
stringifyActivationFailure(ActivationRegionAnalysis::FailureReason reason);

struct ActivationRegionStep {
  const ActivationRegionAnalysis *activation;
  /// The unit's Node::operation.
  mlir::Operation *operation;
};

/// Data inputs of an individual publication, following SSA values, CFG block
/// arguments and the branches that control the store. Unlike a scheduling
/// node, this does not union unrelated computations in the same loop. In
/// ReachingValues mode, reads are incoming value dependencies of each output
/// lane, following definite local stores. Accesses mode conservatively uses
/// the physical read ranges of SSA load inputs.
/// Publication/observer ordering remains a separate scheduling obligation.
struct ActivationPublication {
  mlir::Operation *operation;
  ActivationMemoryAnalysis::Ranges reads, writes;
};
std::optional<llvm::SmallVector<ActivationPublication>>
getActivationPublications(const ActivationRegionAnalysis &activation);

/// Query the publication value graph, independently of source/effect ordering.
/// A DAG here is necessary information for further scheduling refinement, not
/// permission to split or reorder the source activation.
std::optional<llvm::SmallVector<ActivationRegionStep>>
getActivationPublicationOrder(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
    llvm::SmallVectorImpl<ActivationRegionStep> *cycle = nullptr);
/// Topologically order activation units while preserving each original
/// process's source order, SSA dependencies and canonical memory dependencies.
/// Complete typed source-owner provenance permits independent original owners
/// in an existing kernel to interleave. Otherwise retain the whole activation's
/// source order. This is not an activation or observer certificate.
/// On failure, optionally return one directed cycle, without repeating its
/// first step. The steps refer to the input analyses' CFG views.
std::optional<llvm::SmallVector<ActivationRegionStep>> getActivationRegionOrder(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
    llvm::SmallVectorImpl<ActivationRegionStep> *cycle = nullptr);

/// Stores of one activation that execute together, as one clone of that
/// activation's CFG in which every other store is removed.
struct ActivationSlice {
  const ActivationRegionAnalysis *activation;
  llvm::SmallVector<mlir::Operation *> stores;
  /// Lane-copy stores kept only over these root-relative windows; one store
  /// may have several. Emission narrows each such store to its windows.
  llvm::SmallVector<
      std::pair<mlir::Operation *, ActivationMemoryAnalysis::Range>>
      windows;
};
struct ActivationSliceOptions {
  /// Activations whose stores all stay in one slice, in source order
  /// (IEEE 1800-2023 4.6(a)); their statements are never reordered.
  const llvm::DenseSet<const ActivationRegionAnalysis *> *atomic = nullptr;
  /// On failure, every activation with a store inside a dependence cycle.
  llvm::SmallVectorImpl<const ActivationRegionAnalysis *> *cyclic = nullptr;
};

/// Immutable schedule for the input analyses' IR revision. A successful query
/// may contain cycles; failure means unsupported analysis, never feedback.
/// Node identity retains its original activation and source operation. Source
/// order, SSA and snapshot obligations are never cut to break a component.
struct ActivationSchedule {
  enum class DependencyKind { SourceOrder, SSA, Value, Snapshot, Publication };
  struct Dependency {
    unsigned source, target;
    DependencyKind kind;
  };
  llvm::SmallVector<ActivationRegionStep> nodes;
  llvm::SmallVector<Dependency> dependencies;
  llvm::SmallVector<unsigned> order, componentOffsets, componentOf;
  llvm::SmallVector<bool> cyclic;
  /// Original suspension events, separate from value dependencies. Narrowing
  /// a value lane never narrows IEEE 1800-2023 9.2.2.2.1 sensitivity.
  llvm::SmallVector<mlir::Operation *> sensitivityEvents;
  /// Populated only by the slice query, one entry per schedule node.
  llvm::SmallVector<ActivationSlice> slices;
  bool isAcyclic() const {
    return llvm::none_of(cyclic, [](bool value) { return value; });
  }
};

std::optional<ActivationSchedule> getActivationRegionSchedule(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations);
std::optional<ActivationSchedule> getActivationSliceSchedule(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
    const ActivationSliceOptions &options = {});
/// Clone a slice and simplify the now-unneeded control flow. Private stores
/// unrelated to its publications are removed too. The mapping, when supplied,
/// describes the clone before simplification; surviving memory reads retain
/// their operation identity. The original activation is unchanged.
mlir::OwningOpRef<sim::SimFuncOp>
cloneActivationSlice(const ActivationSlice &slice,
                     mlir::IRMapping *mapping = nullptr);
/// Order the stores of all activations by data dependence alone, ignoring each
/// process's statement order, and group consecutive stores of one activation
/// into slices. A store depends on the loads that its value, its address and
/// its execution depend on (SSA values, block arguments and controlling
/// branches). Overlapping stores and source-local store/load dependences share
/// a slice, preserving snapshots and source order. Loops are never unrolled:
/// a slice keeps the complete CFG.
///
/// This is not an observer certificate. Reordering statements of a process is
/// not a reference-algorithm execution (IEEE 1800-2023 4.6(a)); it is valid
/// only under 4.3 when nothing outside the cohort can observe the transitions
/// it removes. On failure, optionally return one directed cycle of stores.
/// Dependences follow lane publications where the activation has value
/// dependencies, so a store depends only on the bits its lanes use; a whole
/// lane-copy store is split into partial stores at the lanes other nodes
/// read or write.
std::optional<llvm::SmallVector<ActivationSlice>> getActivationSliceOrder(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
    llvm::SmallVectorImpl<ActivationRegionStep> *cycle = nullptr,
    const ActivationSliceOptions &options = {});
} // namespace talos::analysis
#endif
