//===- ActivationRegionAnalysis.h - Activation regions ---------*- C++ -*-===//
#ifndef TALOS_ANALYSIS_ACTIVATIONREGIONANALYSIS_H
#define TALOS_ANALYSIS_ACTIVATIONREGIONANALYSIS_H

#include "talos/Analysis/ActivationPreparation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include <memory>

namespace talos::analysis {

/// Read-only facts for a prepared change-sensitive activation. Preparation
/// establishes initial/resume equivalence and bounded-loop termination before
/// construction. The analysis never rewrites its input view. Loops remain in
/// the CFG rather than being unrolled.
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
  using FailureReason = ActivationFailureReason;
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
  ActivationRegionAnalysis(
      PreparedActivation prepared, const HandleDataflowAnalysis &handles,
      ActivationMemoryAnalysis::DependencyMode mode =
          ActivationMemoryAnalysis::DependencyMode::Accesses);
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
  sim::SimFuncOp getSourceFunction() const { return sourceFunction; }
  /// Symbol table resolving the activation's callees.
  mlir::Operation *getSymbolTable() const { return symbols; }
  ActivationMemoryAnalysis::DependencyMode getDependencyMode() const {
    return dependencyMode;
  }
  /// Exact source event ranges, or nullopt for unresolved/dynamic watches.
  const std::optional<Ranges> &getWatchedRanges() const {
    return watchedRanges;
  }
  const ActivationRegionAnalysis *getSourceActivation() const {
    return sourceActivation ? sourceActivation : this;
  }

private:
  ActivationMemoryAnalysis memory;
  mlir::OwningOpRef<sim::SimFuncOp> view;
  llvm::SmallVector<Node> nodes;
  llvm::DenseMap<mlir::Operation *, unsigned> nodeIndices;
  llvm::DenseMap<mlir::Block *, unsigned> argumentNodes;
  mlir::Operation *suspension = nullptr;
  std::optional<Ranges> watchedRanges;
  sim::SimFuncOp sourceFunction;
  mlir::Operation *symbols = nullptr;
  const ActivationRegionAnalysis *sourceActivation = nullptr;
  ActivationMemoryAnalysis::DependencyMode dependencyMode =
      ActivationMemoryAnalysis::DependencyMode::Accesses;
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

/// Explicit, cached preparation of the views needed by interleaving analysis.
/// Call prepare for each cohort before querying its order. Only potentially
/// pulsing, cyclic cohorts need publication-frontier copies. Each copy is
/// frozen before constructing its memory/region analysis; source views remain
/// unchanged. The source views and handle facts must outlive this cache.
class ActivationInterleavingPreparation {
public:
  explicit ActivationInterleavingPreparation(
      const HandleDataflowAnalysis &handles)
      : handles(handles) {}
  void prepare(llvm::ArrayRef<const ActivationRegionAnalysis *> activations);
  const ActivationRegionAnalysis *
  getFrontierView(const ActivationRegionAnalysis *activation) const {
    auto found = frontierViews.find(activation);
    return found == frontierViews.end() ? nullptr : found->second.get();
  }
  unsigned getFrontierActivationCount() const {
    return llvm::count_if(frontierViews,
                          [](const auto &entry) { return bool(entry.second); });
  }

private:
  friend class ActivationInterleavingAnalysis;
  const HandleDataflowAnalysis &handles;
  llvm::DenseMap<const ActivationRegionAnalysis *,
                 std::unique_ptr<ActivationRegionAnalysis>>
      frontierViews;
  bool prepared = false;
  llvm::SmallVector<const ActivationRegionAnalysis *> preparedActivations;
  std::optional<ActivationSchedule> schedule;
};

/// Revision-local analysis of a source-ordered interleaving of combinational
/// activations. Only a strongly connected cycle of unequal publications with
/// jointly satisfiable, stable guards can select a new order. A guard may read
/// another owner's output only through a nonrecursive final-value proof.
/// Otherwise getOrder returns the existing region order unchanged. A cyclic
/// physical-access graph can
/// then be refined with demanded load lanes, including every intermediate
/// publication and control decision. Source order, SSA and local snapshots
/// remain constraints; this never drops events or certifies extra activations.
///
/// Range intersections use an indexed sweep with bounded work. Bit demand is
/// solved only for activations in a cyclic component and cached across cohort
/// queries. Conditional publication frontiers are supplied by explicit
/// preparation; queries never clone or rewrite IR. Returned steps may refer
/// to those prepared views. Preparation and the input activation views must
/// outlive this analysis and remain unchanged during a query. Clients
/// separately prove activation and observer eligibility.
/// Pulse proofs admit up to eight owners and 64 stable external input bits
/// per guard; pulse witnesses and exact handoff searches each visit at most
/// 4096 states. Budget
/// exhaustion or unsupported guards never authorize a new schedule.
class ActivationInterleavingAnalysis {
public:
  explicit ActivationInterleavingAnalysis(
      const ActivationInterleavingPreparation &preparation)
      : preparation(preparation) {}
  std::optional<llvm::SmallVector<ActivationRegionStep>>
  getOrder(llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
           llvm::SmallVectorImpl<ActivationRegionStep> *cycle = nullptr);
  unsigned getRefinedActivationCount() const { return demandedReads.size(); }
  unsigned getFrontierActivationCount() const {
    return preparation.getFrontierActivationCount();
  }
  bool hasProvenLivelock() const { return provenLivelock; }
  /// Minimum handoffs among source-ordered, single-activation schedules that
  /// satisfy the dependence graph and re-arm only after the last publication
  /// of each watched input. Nullopt if the bounded exact search did not finish.
  std::optional<unsigned> getMinimumHandoffs() const { return minimumHandoffs; }
  /// Boundaries of the exact order, immediately before the next unit of an
  /// interrupted actor. A null operation delays only its original re-arm.
  /// These are choices of Active execution, not new source timing controls.
  llvm::ArrayRef<ActivationRegionStep> getPreemptions() const {
    return preemptions;
  }
  /// Every maximal run of the exact solution, including virtual re-arms.
  llvm::ArrayRef<const ActivationRegionAnalysis *> getRuns() const {
    return runs;
  }

private:
  const ActivationInterleavingPreparation &preparation;
  std::optional<llvm::SmallVector<ActivationRegionStep>>
  computeOrder(llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
               llvm::SmallVectorImpl<ActivationRegionStep> *cycle);
  using Reads =
      llvm::DenseMap<mlir::Operation *, ActivationMemoryAnalysis::Ranges>;
  llvm::DenseMap<const ActivationRegionAnalysis *, Reads> demandedReads;
  bool provenLivelock = false;
  std::optional<unsigned> minimumHandoffs;
  llvm::SmallVector<ActivationRegionStep> preemptions;
  llvm::SmallVector<const ActivationRegionAnalysis *> runs;
  bool cached = false;
  bool cachedCycleAvailable = false;
  llvm::SmallVector<const ActivationRegionAnalysis *> cachedActivations;
  std::optional<llvm::SmallVector<ActivationRegionStep>> cachedOrder;
  llvm::SmallVector<ActivationRegionStep> cachedCycle;
};

/// A legal Active-region execution of the original processes, independent of
/// settled-value fusion. Each body stays intact, including reads that capture
/// an earlier publication. Selected processes remain active after their body
/// until other pending Active work has run, then encounter their original
/// event control. No watch, publication or logical process is removed.
struct ActivationRearmPlan {
  using Trace = llvm::function_ref<void(const ActivationRegionAnalysis *,
                                        mlir::Value, llvm::StringRef)>;
  llvm::SmallVector<const ActivationRegionAnalysis *> preemptions;
  /// Whole-body run order selected by the exact search, before virtual re-arms.
  llvm::SmallVector<const ActivationRegionAnalysis *> bodyOrder;
  /// Complete maximal-run order, including the virtual re-arms.
  llvm::SmallVector<const ActivationRegionAnalysis *> runs;
  /// Exact minimum for whole-body executions followed by their original
  /// re-arms, counting only handoffs within this cohort. This is not an
  /// optimum over arbitrary source-statement interleavings or outside work.
  unsigned minimumHandoffs = 0;
};
/// Fast potential pulse SCCs, indexed by source watched ranges. Only original
/// always_comb owners with repeated publications participate. A component is
/// a candidate, not a proof of livelock or permission to change its schedule.
llvm::SmallVector<llvm::SmallVector<const ActivationRegionAnalysis *>>
getActivationPulseComponents(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations);
/// Empty preemptions preserve the schedule when no pulse-cycle witness was
/// proved. Unsupported or exhausted exact searches return nullopt. At most
/// eight owners and 4096 search states; neither query mutates source IR.
std::optional<ActivationRearmPlan> getActivationRearmPlan(
    llvm::ArrayRef<const ActivationRegionAnalysis *> activations,
    ActivationRearmPlan::Trace trace = {});

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
/// Retained-state activations always keep all their stores together, including
/// implicit holds: stable-input idempotence cannot authorize moving a capture
/// after later source publications that change its enable through feedback.
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
