//===- StaticSpecializationAnalysis.h - Validate static plans ---*- C++ -*-===//
//
// A shared, read-only view of the revision-coupled static state and NBA plan.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_ANALYSIS_STATICSPECIALIZATIONANALYSIS_H
#define TALOS_ANALYSIS_STATICSPECIALIZATIONANALYSIS_H

#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

#include <cstdint>

namespace talos::analysis {

/// Validates static-specialization metadata against its source design and
/// derives the NBA site inventory consumed by both native and bytecode
/// lowering.
///
/// The analyzed design must remain alive and unchanged for this object's
/// lifetime. Recompute the analysis after mutating the design or its graph.
class StaticSpecializationAnalysis {
public:
  static mlir::FailureOr<StaticSpecializationAnalysis>
  compute(sim::SimDesignOp design);

  explicit operator bool() const { return plan != nullptr; }
  schedule::StaticSpecializationAttr getPlan() const { return plan; }

  const llvm::DenseMap<uint64_t, schedule::StaticStateRootAttr> &
  getRoots() const {
    return roots;
  }
  mlir::ArrayRef<uint64_t> getNBARoots() const { return nbaRoots; }
  const llvm::DenseSet<uint64_t> &getNBASites() const { return nbaSites; }
  mlir::ArrayRef<schedule::ComputeNBACommitAttr> getOrderedNBACommits() const {
    return orderedNBACommits;
  }

private:
  schedule::StaticSpecializationAttr plan;
  llvm::DenseMap<uint64_t, schedule::StaticStateRootAttr> roots;
  mlir::SmallVector<uint64_t> nbaRoots;
  llvm::DenseSet<uint64_t> nbaSites;
  mlir::SmallVector<schedule::ComputeNBACommitAttr> orderedNBACommits;
};

/// Site identities of the clocking-block output drives under `root`. Such a
/// drive updates its signal in the Re-NBA region (IEEE 1800-2023 14.16), never
/// at the NBA barrier that static NBA accumulators share.
llvm::DenseSet<int64_t> collectClockingDriveSites(mlir::Operation *root);

/// Whether `commit` names no single storage root yet has a site other than a
/// clocking-block drive (`clockingDriveSites`). Such a commit, an NBA through
/// a virtual interface for instance, may write any static NBA root, so none
/// may commit from an accumulator ahead of it (IEEE 1800-2023 4.6(b),
/// 10.4.2, 25.9): static specialization then plans no NBA root, and the
/// native NBA plan rejects one beside it. Local and net commits count too,
/// conservatively; nonblocking assignments to neither are legal (10.4.2).
bool isUnrootedNBACommit(schedule::ComputeNBACommitAttr commit,
                         const llvm::DenseSet<int64_t> &clockingDriveSites);

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_STATICSPECIALIZATIONANALYSIS_H
