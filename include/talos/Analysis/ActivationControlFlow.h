//===- ActivationControlFlow.h - Normalize activation proof CFGs -*- C++
//-*-===//
#ifndef TALOS_ANALYSIS_ACTIVATIONCONTROLFLOW_H
#define TALOS_ANALYSIS_ACTIVATIONCONTROLFLOW_H

#include "mlir/IR/Region.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace talos::sim {
class SimDesignOp;
class SimFuncOp;
} // namespace talos::sim

namespace talos::analysis {
/// Apply ordinary operation folders and dialect/arith/cf control patterns to
/// a disposable activation or emitted slice. Keeps publication operations
/// intact; run before deriving revision-dependent facts. Semantic folding
/// rules belong to the dialect, rather than to activation analysis.
mlir::LogicalResult
canonicalizeActivationControlFlow(mlir::Operation *operation);

/// A named block activation is unobservable only if its target has no disable
/// or nonlocal exit anywhere in this revision, its token has only leave users,
/// and its process has no deferred reports owned by that activation, including
/// reports from callees (9.6.2, 16.4.1). One whole-design index serves every
/// view. The source design must remain unchanged while these facts are queried.
class ControlActivationAnalysis {
public:
  explicit ControlActivationAnalysis(sim::SimDesignOp design);
  llvm::ArrayRef<mlir::Operation *>
  getUnobservableEnters(sim::SimFuncOp function) const;

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::Operation *>>
      enters;
};

/// Thread proved constant edges through pure dispatch blocks in a disposable
/// activation CFG. Dense must-predicate facts meet at joins; sparse folding
/// translates the dispatch condition through each predecessor's SSA operands.
/// No memory operation, loop body or unknown branch is duplicated or removed.
/// Returns whether any edge changed. Recompute all analyses after a change.
bool threadActivationControlFlow(mlir::Region &region);
/// Specialize small, acyclic shared tails with handle arguments on their
/// incoming edges. Each path executes exactly the same operations, with the
/// same reference operands and snapshots. This exposes static aliases before
/// deriving memory/compute-graph facts. Does not split or interleave processes.
/// Apply to disposable views or before publishing CFG-dependent analyses.
bool specializeStaticHandleTails(
    mlir::Region &region,
    llvm::function_ref<bool(mlir::Block *)> eligible = {});
} // namespace talos::analysis
#endif
