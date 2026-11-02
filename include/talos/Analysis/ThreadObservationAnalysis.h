#ifndef TALOS_ANALYSIS_THREADOBSERVATIONANALYSIS_H
#define TALOS_ANALYSIS_THREADOBSERVATIONANALYSIS_H

#include "mlir/IR/Operation.h"
#include "llvm/ADT/DenseMap.h"

namespace talos::analysis {

/// Whether a function's complete executable closure can observe the process
/// that executes it as a thread: its identity and per-process state
/// (process::self and the process class, IEEE 1800-2023 9.7; the process RNG,
/// 18.14.1), named blocks that a disable can target (9.6.2), processes it forks
/// (9.3.2), and context DPI imports, which can reach any exported subroutine
/// (35.5.3). Simulation and lowered LLVM functions are both nodes of the call
/// graph; recursive SCCs and unresolved or dynamic callees are conservative.
class ThreadObservationAnalysis {
public:
  explicit ThreadObservationAnalysis(mlir::Operation *root);
  /// Whether `function` (a simulation or LLVM function under the root) may
  /// observe its executing thread. Functions outside the root are assumed to.
  bool observes(mlir::Operation *function) const;

private:
  llvm::DenseMap<mlir::Operation *, bool> observing;
};

/// Whether one operation, ignoring its callees, observes the executing thread.
bool observesExecutingThread(mlir::Operation *operation);

} // namespace talos::analysis
#endif
