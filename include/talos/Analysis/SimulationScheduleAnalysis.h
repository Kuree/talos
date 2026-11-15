//===- SimulationScheduleAnalysis.h - Shared schedule ranks ----*- C++ -*-===//
//
// Read-only process and continuation ordering derived from the compute graph.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_ANALYSIS_SIMULATIONSCHEDULEANALYSIS_H
#define TALOS_ANALYSIS_SIMULATIONSCHEDULEANALYSIS_H

#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace talos::analysis {

/// Resolve a compute-graph block ordinal, excluding transient observer capture
/// bridge blocks that are not part of the graph ABI.
mlir::Block *lookupComputeGraphBlock(sim::SimFuncOp function, uint32_t ordinal);

/// Resolves many compute-graph block ordinals against one IR revision. Each
/// function's ordinal table is built on first use, so a whole-graph sweep stays
/// linear in the fused body size. Indexed functions must not gain, lose, or
/// reorder blocks while the index is alive.
class ComputeGraphBlockIndex {
public:
  mlir::Block *lookup(sim::SimFuncOp function, uint32_t ordinal);

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::Block *>> blocks;
};

bool isSettlingEntryKind(sim::EntryKind kind);

/// The implicit time-zero ordering for spawns in one root-initializer block
/// and event region. Keeping the two sets avoids storing their Cartesian
/// product as process_order edges. These are scheduling constraints, not CFG
/// successors: they must not participate in continuation closures.
struct StartupPhase {
  llvm::SmallVector<uint32_t> startups;
  llvm::SmallVector<uint32_t> initials;
};

llvm::SmallVector<StartupPhase> collectStartupPhases(
    sim::SimDesignOp design,
    llvm::function_ref<std::optional<uint32_t>(sim::SimFuncOp)> entryID);

/// Include the work resumed by a settling publication in activation ordering.
/// Resume/spawn edges themselves remain boundaries. The returned edges may
/// contain duplicates; consumers normalize their own adjacency representation.
llvm::SmallVector<schedule::ComputeEdgeAttr> projectActivationSchedulingEdges(
    llvm::ArrayRef<schedule::ComputeEdgeAttr> edges,
    llvm::function_ref<bool(uint32_t)> isSettlingSource);

/// Deterministic scheduler ranks shared by native and bytecode execution.
class SimulationScheduleAnalysis {
public:
  static mlir::FailureOr<SimulationScheduleAnalysis>
  compute(mlir::ModuleOp module);
  static mlir::FailureOr<SimulationScheduleAnalysis>
  compute(sim::SimDesignOp design);

  std::optional<uint32_t> getEntryRank(mlir::Operation *function) const;
  std::optional<uint32_t> getBlockRank(mlir::Block *block) const;

  /// Independent, transitive Active producers of inputs read before an
  /// interrupted actor's first handoff. They must settle before its first
  /// read: a publication during its partial execution cannot wake its already
  /// completed event control (9.4.2). Value-dependent feedback uses the source
  /// handoff order instead. Unrelated outputs of one producer stay separate.
  llvm::ArrayRef<sim::SimFuncOp>
  getPreemptionPrerequisites(mlir::Operation *function) const;
  /// Interrupted actors with an input read before their first handoff whose
  /// producers could not be proved independent of the cohort. Realizing
  /// their handoffs could expose partial state or lose an update.
  const llvm::DenseSet<mlir::Operation *> &
  getUnprovedPreemptionOwners() const {
    return unprovedPreemptionOwners;
  }

  const llvm::DenseMap<mlir::Operation *, uint32_t> &getEntryRanks() const {
    return entryRanks;
  }
  const llvm::DenseMap<mlir::Block *, uint32_t> &getBlockRanks() const {
    return blockRanks;
  }

private:
  llvm::DenseMap<mlir::Operation *, uint32_t> entryRanks;
  llvm::DenseMap<mlir::Block *, uint32_t> blockRanks;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<sim::SimFuncOp>>
      preemptionPrerequisites;
  llvm::DenseSet<mlir::Operation *> unprovedPreemptionOwners;
};

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_SIMULATIONSCHEDULEANALYSIS_H
