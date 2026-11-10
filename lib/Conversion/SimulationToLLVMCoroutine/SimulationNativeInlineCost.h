//===- SimulationNativeInlineCost.h - Native inline growth costs -*- C++
//-*-===//

#ifndef TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H
#define TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H

#include "SimulationEvalReadySet.h"

namespace talos::detail {

inline uint64_t nativeOperationCost(mlir::Operation *operation) {
  if (auto merge = mlir::dyn_cast<schedule::NativeReadyMergeOp>(operation)) {
    EvalReadySetLayout layout(merge.getCapacity());
    // A bounded word loop has one add body, independent of the number of
    // leaves. A partial last word adds a second body after the loop, and at
    // least two eight-word groups of unmasked words add the fixed group and
    // tail tests (materializeReadyMerge).
    uint64_t addCost = 24 * layout.levels;
    uint64_t cost = 24 + addCost;
    uint64_t span = layout.counts[0];
    if (layout.lastWordMask() != UINT64_MAX) {
      cost += 8 + addCost;
      --span;
    }
    if (span >= 16)
      cost += 24;
    return cost;
  }
  uint64_t capacity = 0;
  if (auto update = mlir::dyn_cast<schedule::NativeReadyUpdateOp>(operation))
    capacity = update.getCapacity();
  else if (auto commit =
               mlir::dyn_cast<schedule::NativeReadyCommitOp>(operation))
    capacity = commit.getCapacity();
  if (capacity) {
    EvalReadySetLayout layout(capacity);
    // Charge deferred leaf/index maintenance before action lowering expands it.
    return 12 * layout.levels;
  }
  return mlir::isa<schedule::NativeReadyReadOp>(operation) ? 2 : 1;
}

inline uint64_t nativeInlineCost(mlir::Operation *root) {
  uint64_t cost = 0;
  root->walk([&](mlir::Operation *operation) {
    if (operation != root)
      cost += nativeOperationCost(operation);
  });
  return cost;
}

} // namespace talos::detail

#endif
