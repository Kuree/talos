//===- SimulationEvalReadySet.h - Word-wise generated owner sets -*- C++
//-*-===//

#ifndef TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_EVAL_READY_SET_H
#define TALOS_LIB_CONVERSION_SIMULATIONTOLLVMCOROUTINE_EVAL_READY_SET_H

#include "SimulationToLLVMCoroutinePrivate.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Runtime/ClockKernelReadySet.h"
#include <map>

namespace talos::detail {

/// Layout of every generated eval ready set: the model ingress and the NBA
/// held wakes (runtime::DirtyReadySetLayout).
using EvalReadySetLayout = runtime::DirtyReadySetLayout;

/// Whether a direct call to `callee` can neither inspect nor change any ready
/// set: it executes no actor and does not enter the scheduler. Pending ready
/// words may stay local across such a call.
bool isReadinessTransparentCallee(llvm::StringRef callee);

// APInt is only a compiler-side constant set. Generated storage and operations
// are always machine words, never wide LLVM integers.
inline uint64_t ownerMaskWord(const llvm::APInt &mask, unsigned word) {
  return mask.getRawData()[word];
}

inline mlir::Value ownerWordAddress(mlir::OpBuilder &builder,
                                    mlir::Location loc, mlir::Value base,
                                    unsigned word) {
  if (word == 0)
    return base;
  return byteGEP(builder, loc, base, uint64_t{word} * sizeof(uint64_t));
}

// The union of the words of `mask`, each read by `load` and masked.
inline mlir::Value maskedWords(mlir::OpBuilder &builder, mlir::Location loc,
                               const llvm::APInt &mask,
                               llvm::function_ref<mlir::Value(unsigned)> load) {
  auto i64 = builder.getI64Type();
  mlir::Value any;
  for (unsigned word = 0; word != mask.getNumWords(); ++word) {
    uint64_t bits = ownerMaskWord(mask, word);
    if (!bits)
      continue;
    mlir::Value selected = load(word);
    if (bits != UINT64_MAX)
      selected = mlir::arith::AndIOp::create(
          builder, loc, selected, llvmConstant(builder, loc, i64, bits));
    any = any ? mlir::arith::OrIOp::create(builder, loc, any, selected)
              : selected;
  }
  return any ? any : llvmConstant(builder, loc, i64, 0);
}

// A word of a generated eval ready set, read or written whole: word `word`,
// or the word `index` selects (an i64).
inline mlir::Value loadReadyWord(mlir::OpBuilder &builder, mlir::Location loc,
                                 schedule::ReadySet set, unsigned word) {
  return schedule::NativeReadyWordLoadOp::create(builder, loc, set,
                                                 mlir::Value{}, word);
}
inline mlir::Value loadReadyWordAt(mlir::OpBuilder &builder, mlir::Location loc,
                                   schedule::ReadySet set, mlir::Value index) {
  return schedule::NativeReadyWordLoadOp::create(builder, loc, set, index, 0);
}
inline void storeReadyWord(mlir::OpBuilder &builder, mlir::Location loc,
                           mlir::Value value, schedule::ReadySet set,
                           unsigned word) {
  schedule::NativeReadyWordStoreOp::create(builder, loc, value, set,
                                           mlir::Value{}, word);
}
inline void storeReadyWordAt(mlir::OpBuilder &builder, mlir::Location loc,
                             mlir::Value value, schedule::ReadySet set,
                             mlir::Value index) {
  schedule::NativeReadyWordStoreOp::create(builder, loc, value, set, index, 0);
}

// The union of the words of `mask` in a ready set.
inline mlir::Value maskedReadyWords(mlir::OpBuilder &builder,
                                    mlir::Location loc, schedule::ReadySet set,
                                    const llvm::APInt &mask) {
  return maskedWords(builder, loc, mask, [&](unsigned word) {
    return loadReadyWord(builder, loc, set, word);
  });
}

// A word of a generated eval mask, read or written whole: word `word`, or
// the word `index` selects (an i64). A mask holds proofs, not pending
// activations; see schedule::EvalMask.
inline mlir::Value loadMaskWord(mlir::OpBuilder &builder, mlir::Location loc,
                                schedule::EvalMask mask, unsigned word) {
  return schedule::NativeMaskLoadOp::create(builder, loc, mask, mlir::Value{},
                                            word);
}
inline mlir::Value loadMaskWordAt(mlir::OpBuilder &builder, mlir::Location loc,
                                  schedule::EvalMask mask, mlir::Value index) {
  return schedule::NativeMaskLoadOp::create(builder, loc, mask, index, 0);
}
inline void storeMaskWord(mlir::OpBuilder &builder, mlir::Location loc,
                          mlir::Value value, schedule::EvalMask mask,
                          unsigned word) {
  schedule::NativeMaskStoreOp::create(builder, loc, value, mask, mlir::Value{},
                                      word);
}
inline void storeMaskWordAt(mlir::OpBuilder &builder, mlir::Location loc,
                            mlir::Value value, schedule::EvalMask mask,
                            mlir::Value index) {
  schedule::NativeMaskStoreOp::create(builder, loc, value, mask, index, 0);
}

// The union of the words of `bits` in a generated eval mask.
inline mlir::Value maskedMaskWords(mlir::OpBuilder &builder, mlir::Location loc,
                                   schedule::EvalMask mask,
                                   const llvm::APInt &bits) {
  return maskedWords(builder, loc, bits, [&](unsigned word) {
    return loadMaskWord(builder, loc, mask, word);
  });
}

// Write every word of `bits` to a generated eval mask.
inline void storeMaskWords(mlir::OpBuilder &builder, mlir::Location loc,
                           schedule::EvalMask mask, const llvm::APInt &bits) {
  for (unsigned word = 0; word != bits.getNumWords(); ++word)
    storeMaskWord(builder, loc,
                  llvmConstant(builder, loc, builder.getI64Type(),
                               ownerMaskWord(bits, word)),
                  mask, word);
}

// Add `bits` (an i64) to word `word` of a generated eval mask.
inline void addMaskWord(mlir::OpBuilder &builder, mlir::Location loc,
                        schedule::EvalMask mask, unsigned word,
                        mlir::Value bits) {
  storeMaskWord(builder, loc,
                mlir::arith::OrIOp::create(
                    builder, loc, loadMaskWord(builder, loc, mask, word), bits),
                mask, word);
}

// Add `mask` to word `word` of a ready set, or remove it with `clear`.
inline mlir::Value updateReadyWord(mlir::OpBuilder &builder, mlir::Location loc,
                                   schedule::ReadySet set, unsigned word,
                                   mlir::Value mask, bool clear = false) {
  mlir::Value previous = loadReadyWord(builder, loc, set, word);
  mlir::Value next;
  if (clear) {
    mlir::Value inverse = mlir::arith::XOrIOp::create(
        builder, loc, mask,
        llvmConstant(builder, loc, builder.getI64Type(), UINT64_MAX));
    next = mlir::arith::AndIOp::create(builder, loc, previous, inverse);
  } else {
    next = mlir::arith::OrIOp::create(builder, loc, previous, mask);
  }
  storeReadyWord(builder, loc, next, set, word);
  return next;
}

// Whether an add mask may publish: folded to a constant when it is one.
inline mlir::Value evalReadyAddNonzero(mlir::OpBuilder &builder,
                                       mlir::Location loc, mlir::Value added) {
  return builder.createOrFold<mlir::arith::CmpIOp>(
      loc, mlir::arith::CmpIPredicate::ne, added,
      llvmConstant(builder, loc, builder.getI64Type(), 0));
}

// OR the dirty bits of one leaf that received `added` into every level above
// it (see runtime::DirtyReadySetLayout). An add that may be empty contributes
// its bits under that condition; a consume never touches the dirty levels, so
// a dirty bit is a superset of the nonempty children that the coordinator's
// sweep clears once it observes the child empty. Membership and selection
// order are unchanged; the index carries no event history (IEEE 1800-2023 4.3,
// 4.5--4.7).
inline void materializeEvalReadyIndexes(mlir::OpBuilder &builder,
                                        mlir::Location loc,
                                        schedule::ReadySet set,
                                        const EvalReadySetLayout &layout,
                                        unsigned word, mlir::Value added) {
  using namespace mlir;
  if (!added || !layout.hasSummaries())
    return;
  auto i64 = builder.getI64Type();
  Value nonzero = evalReadyAddNonzero(builder, loc, added);
  if (matchPattern(nonzero, m_Zero()))
    return;
  unsigned child = word;
  for (unsigned level = 1; level != layout.levels; ++level) {
    unsigned parent = layout.offsets[level] + child / 64;
    Value childBit =
        llvmConstant(builder, loc, i64, uint64_t{1} << (child % 64));
    Value bit = builder.createOrFold<arith::SelectOp>(
        loc, nonzero, childBit, llvmConstant(builder, loc, i64, 0));
    Value next = builder.createOrFold<arith::OrIOp>(
        loc, loadReadyWord(builder, loc, set, parent), bit);
    storeReadyWord(builder, loc, next, set, parent);
    child /= 64;
  }
}

inline void materializeEvalReadyWord(mlir::OpBuilder &builder,
                                     mlir::Location loc, schedule::ReadySet set,
                                     const EvalReadySetLayout &layout,
                                     unsigned word, mlir::Value mask,
                                     bool clear = false) {
  updateReadyWord(builder, loc, set, word, mask, clear);
  if (!clear)
    materializeEvalReadyIndexes(builder, loc, set, layout, word, mask);
}

struct EvalReadyWordChange {
  unsigned word;
  mlir::Value remove, add;
};

// Compose typed pending-set actions in source order, then write each final leaf
// and dirty word once. These actions carry no event history (LRM 4.5--4.7).
// The caller must stop at reads, aliases, callbacks and selection boundaries.
inline void
materializeEvalReadyWords(mlir::OpBuilder &builder, mlir::Location loc,
                          schedule::ReadySet set,
                          const EvalReadySetLayout &layout,
                          llvm::ArrayRef<EvalReadyWordChange> changes) {
  using namespace mlir;
  auto i64 = builder.getI64Type();
  Value ones = llvmConstant(builder, loc, i64, UINT64_MAX);
  std::map<unsigned, Value> leaves;
  // Per word of the current level: whether it may have received an add.
  std::map<unsigned, Value> added;
  for (const auto &change : changes) {
    Value previous = leaves.count(change.word)
                         ? leaves.at(change.word)
                         : loadReadyWord(builder, loc, set, change.word);
    Value inverse =
        builder.createOrFold<arith::XOrIOp>(loc, change.remove, ones);
    Value retained =
        builder.createOrFold<arith::AndIOp>(loc, previous, inverse);
    leaves[change.word] =
        builder.createOrFold<arith::OrIOp>(loc, retained, change.add);
    Value nonzero = evalReadyAddNonzero(builder, loc, change.add);
    if (matchPattern(nonzero, m_Zero()))
      continue;
    Value &any = added[change.word];
    any = any ? builder.createOrFold<arith::OrIOp>(loc, any, nonzero) : nonzero;
  }
  for (auto [word, next] : leaves)
    storeReadyWord(builder, loc, next, set, word);
  for (unsigned level = 1; level != layout.levels && !added.empty(); ++level) {
    std::map<unsigned, Value> parents, parentAdded;
    for (auto [child, nonzero] : added) {
      unsigned parent = child / 64;
      Value previous = parents.count(parent)
                           ? parents.at(parent)
                           : loadReadyWord(builder, loc, set,
                                           layout.offsets[level] + parent);
      Value childBit =
          llvmConstant(builder, loc, i64, uint64_t{1} << (child % 64));
      Value bit = builder.createOrFold<arith::SelectOp>(
          loc, nonzero, childBit, llvmConstant(builder, loc, i64, 0));
      parents[parent] = builder.createOrFold<arith::OrIOp>(loc, previous, bit);
      Value &any = parentAdded[parent];
      any =
          any ? builder.createOrFold<arith::OrIOp>(loc, any, nonzero) : nonzero;
    }
    for (auto [parent, next] : parents)
      storeReadyWord(builder, loc, next, set, layout.offsets[level] + parent);
    added = std::move(parentAdded);
  }
}

inline void updateEvalReadyWord(mlir::OpBuilder &builder, mlir::Location loc,
                                schedule::ReadySet set,
                                const EvalReadySetLayout &layout, unsigned word,
                                mlir::Value mask, bool clear = false) {
  schedule::NativeReadyUpdateOp::create(builder, loc, set, mask,
                                        layout.capacity, word, clear);
}

// Add the words of `mask`, selected by `condition` when given, to a ready set
// as ready updates, or remove them with `clear`.
inline void updateReadyMask(mlir::OpBuilder &builder, mlir::Location loc,
                            schedule::ReadySet set,
                            const EvalReadySetLayout &layout,
                            const llvm::APInt &mask, bool clear = false,
                            mlir::Value condition = {}) {
  auto i64 = builder.getI64Type();
  for (unsigned word = 0; word != mask.getNumWords(); ++word) {
    uint64_t bits = ownerMaskWord(mask, word);
    if (!bits)
      continue;
    mlir::Value selected = llvmConstant(builder, loc, i64, bits);
    if (condition)
      selected =
          mlir::arith::SelectOp::create(builder, loc, condition, selected,
                                        llvmConstant(builder, loc, i64, 0));
    updateEvalReadyWord(builder, loc, set, layout, word, selected, clear);
  }
}

} // namespace talos::detail
#endif
