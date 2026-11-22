//===- SimulationNativeInlineCost.h - Native inline growth costs -*- C++
//-*-===//

#ifndef TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H
#define TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_NATIVE_INLINE_COST_H

#include "SimulationEvalReadySet.h"

namespace talos::detail {

/// The global a ready action, ready set word access or mask word access
/// names.
inline mlir::FlatSymbolRefAttr getNativeWordGlobal(mlir::Operation *operation) {
  if (auto update = mlir::dyn_cast<schedule::NativeReadyUpdateOp>(operation))
    return update.getSetAttr();
  if (auto commit = mlir::dyn_cast<schedule::NativeReadyCommitOp>(operation))
    return commit.getSetAttr();
  if (auto read = mlir::dyn_cast<schedule::NativeReadyReadOp>(operation))
    return read.getSetAttr();
  if (auto merge = mlir::dyn_cast<schedule::NativeReadyMergeOp>(operation))
    return merge.getSetAttr();
  if (auto load = mlir::dyn_cast<schedule::NativeReadyWordLoadOp>(operation))
    return load.getSetAttr();
  if (auto store = mlir::dyn_cast<schedule::NativeReadyWordStoreOp>(operation))
    return store.getSetAttr();
  if (auto load = mlir::dyn_cast<schedule::NativeMaskLoadOp>(operation))
    return load.getMaskAttr();
  if (auto store = mlir::dyn_cast<schedule::NativeMaskStoreOp>(operation))
    return store.getMaskAttr();
  return {};
}

/// The operations `operation` stands for in LLVM IR, as op-count budgets
/// count them: an NBA accumulator field or readiness index access is its
/// address computation and the access; a ready set or mask word access is
/// the access and the GEPs to its word, an i64 GEP by a dynamic word and a
/// byte GEP to a nonzero static word, of its global's address
/// (nativeWordGlobalAddressCost). Accesses of one dynamic word in one block
/// share its GEPs in the LLVM form (lower-native-ready-words); each is still
/// charged them here, an over-count that only makes a budget stricter.
inline uint64_t nativeLoweredSize(mlir::Operation *operation) {
  auto wordSize = [](mlir::Value dynamicWord, uint64_t staticWord) {
    return uint64_t{1} + bool(dynamicWord) + (staticWord != 0);
  };
  if (auto load = mlir::dyn_cast<schedule::NativeReadyWordLoadOp>(operation))
    return wordSize(load.getDynamicWord(), load.getStaticWord());
  if (auto store = mlir::dyn_cast<schedule::NativeReadyWordStoreOp>(operation))
    return wordSize(store.getDynamicWord(), store.getStaticWord());
  if (auto load = mlir::dyn_cast<schedule::NativeMaskLoadOp>(operation))
    return wordSize(load.getDynamicWord(), load.getStaticWord());
  if (auto store = mlir::dyn_cast<schedule::NativeMaskStoreOp>(operation))
    return wordSize(store.getDynamicWord(), store.getStaticWord());
  return mlir::isa<schedule::NativeNBAAccumulatorLoadOp,
                   schedule::NativeNBAAccumulatorStoreOp,
                   schedule::NativeNBAIndexLoadOp,
                   schedule::NativeNBAIndexStoreOp>(operation)
             ? 2
             : 1;
}

/// The addresses of ready sets and masks the LLVM form of `root`'s ready
/// actions and word accesses takes: one per global each function names (as
/// lower-native-ready-words, lower-native-mask-words and action lowering take
/// them).
inline uint64_t nativeWordGlobalAddressCost(mlir::Operation *root) {
  llvm::SmallVector<mlir::Attribute, 4> globals;
  root->walk([&](mlir::Operation *operation) {
    mlir::FlatSymbolRefAttr global = getNativeWordGlobal(operation);
    if (global && !llvm::is_contained(globals, global))
      globals.push_back(global);
  });
  return globals.size();
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

/// The operations nested in `root` cost, with the ready set and mask
/// addresses their LLVM form shares.
inline uint64_t nativeInlineCost(mlir::Operation *root) {
  uint64_t cost = 0;
  root->walk([&](mlir::Operation *operation) {
    if (operation != root)
      cost += nativeOperationCost(operation);
  });
  return cost + nativeWordGlobalAddressCost(root);
}

} // namespace talos::detail

#endif
