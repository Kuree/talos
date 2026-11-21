//===- SimulationNativeInlineCost.h - Native inline growth costs -*- C++
//-*-===//

#ifndef TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H
#define TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H

#include "SimulationEvalReadySet.h"

namespace talos::detail {

/// The operations `operation` stands for in LLVM IR, as op-count budgets
/// count them: an NBA accumulator field, readiness index or ready set word
/// access is its address computation and the access.
inline uint64_t nativeLoweredSize(mlir::Operation *operation) {
  return mlir::isa<
             schedule::NativeNBAAccumulatorLoadOp,
             schedule::NativeNBAAccumulatorStoreOp,
             schedule::NativeNBAIndexLoadOp, schedule::NativeNBAIndexStoreOp,
             schedule::NativeReadyWordLoadOp, schedule::NativeReadyWordStoreOp>(
             operation)
             ? 2
             : 1;
}

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
  return mlir::isa<schedule::NativeReadyReadOp>(operation)
             ? 2
             : nativeLoweredSize(operation);
}

/// The operations nested in `root` cost. Ready actions and word accesses
/// name their set; in LLVM IR a function shares one address of each set
/// (ReadySetAddresses), so a set that `root` addresses only through them is
/// charged that address once.
inline uint64_t nativeInlineCost(mlir::Operation *root) {
  uint64_t cost = 0;
  llvm::SmallVector<mlir::StringAttr, 2> readySets, addressed;
  root->walk([&](mlir::Operation *operation) {
    if (operation == root)
      return;
    cost += nativeOperationCost(operation);
    mlir::FlatSymbolRefAttr set;
    if (auto update = mlir::dyn_cast<schedule::NativeReadyUpdateOp>(operation))
      set = update.getSetAttr();
    else if (auto commit =
                 mlir::dyn_cast<schedule::NativeReadyCommitOp>(operation))
      set = commit.getSetAttr();
    else if (auto read = mlir::dyn_cast<schedule::NativeReadyReadOp>(operation))
      set = read.getSetAttr();
    else if (auto merge =
                 mlir::dyn_cast<schedule::NativeReadyMergeOp>(operation))
      set = merge.getSetAttr();
    else if (auto load =
                 mlir::dyn_cast<schedule::NativeReadyWordLoadOp>(operation))
      set = load.getSetAttr();
    else if (auto store =
                 mlir::dyn_cast<schedule::NativeReadyWordStoreOp>(operation))
      set = store.getSetAttr();
    auto address = mlir::dyn_cast<mlir::LLVM::AddressOfOp>(operation);
    if (address && schedule::getReadySetOfGlobal(address.getGlobalName()) &&
        !llvm::is_contained(addressed, address.getGlobalNameAttr().getAttr()))
      addressed.push_back(address.getGlobalNameAttr().getAttr());
    if (set && !llvm::is_contained(readySets, set.getAttr()))
      readySets.push_back(set.getAttr());
  });
  for (mlir::StringAttr set : readySets)
    cost += !llvm::is_contained(addressed, set);
  return cost;
}

} // namespace talos::detail

#endif
