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

inline mlir::Value loadOwnerWord(mlir::OpBuilder &builder, mlir::Location loc,
                                 mlir::Value base, unsigned word) {
  return mlir::LLVM::LoadOp::create(builder, loc, builder.getI64Type(),
                                    ownerWordAddress(builder, loc, base, word),
                                    8);
}

inline mlir::Value maskedOwnerWords(mlir::OpBuilder &builder,
                                    mlir::Location loc, mlir::Value base,
                                    const llvm::APInt &mask) {
  auto i64 = builder.getI64Type();
  mlir::Value any;
  for (unsigned word = 0; word != mask.getNumWords(); ++word) {
    uint64_t bits = ownerMaskWord(mask, word);
    if (!bits)
      continue;
    mlir::Value selected = loadOwnerWord(builder, loc, base, word);
    if (bits != UINT64_MAX)
      selected = mlir::arith::AndIOp::create(
          builder, loc, selected, llvmConstant(builder, loc, i64, bits));
    any = any ? mlir::arith::OrIOp::create(builder, loc, any, selected)
              : selected;
  }
  return any ? any : llvmConstant(builder, loc, i64, 0);
}

inline void storeOwnerMask(mlir::OpBuilder &builder, mlir::Location loc,
                           mlir::Value base, const llvm::APInt &mask) {
  for (unsigned word = 0; word != mask.getNumWords(); ++word)
    mlir::LLVM::StoreOp::create(builder, loc,
                                llvmConstant(builder, loc, builder.getI64Type(),
                                             ownerMaskWord(mask, word)),
                                ownerWordAddress(builder, loc, base, word), 8);
}

inline mlir::Value updateOwnerWord(mlir::OpBuilder &builder, mlir::Location loc,
                                   mlir::Value base, unsigned word,
                                   mlir::Value mask, bool clear = false) {
  mlir::Value previous = loadOwnerWord(builder, loc, base, word);
  mlir::Value next;
  if (clear) {
    mlir::Value inverse = mlir::arith::XOrIOp::create(
        builder, loc, mask,
        llvmConstant(builder, loc, builder.getI64Type(), UINT64_MAX));
    next = mlir::arith::AndIOp::create(builder, loc, previous, inverse);
  } else {
    next = mlir::arith::OrIOp::create(builder, loc, previous, mask);
  }
  mlir::LLVM::StoreOp::create(builder, loc, next,
                              ownerWordAddress(builder, loc, base, word), 8);
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
                                        mlir::Location loc, mlir::Value base,
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
    Value bit = builder.createOrFold<arith::SelectOp>(
        loc, nonzero,
        llvmConstant(builder, loc, i64, uint64_t{1} << (child % 64)),
        llvmConstant(builder, loc, i64, 0));
    Value next = builder.createOrFold<arith::OrIOp>(
        loc, loadOwnerWord(builder, loc, base, parent), bit);
    LLVM::StoreOp::create(builder, loc, next,
                          ownerWordAddress(builder, loc, base, parent), 8);
    child /= 64;
  }
}

inline void materializeEvalReadyWord(mlir::OpBuilder &builder,
                                     mlir::Location loc, mlir::Value base,
                                     const EvalReadySetLayout &layout,
                                     unsigned word, mlir::Value mask,
                                     bool clear = false) {
  updateOwnerWord(builder, loc, base, word, mask, clear);
  if (!clear)
    materializeEvalReadyIndexes(builder, loc, base, layout, word, mask);
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
                          mlir::Value base, const EvalReadySetLayout &layout,
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
                         : loadOwnerWord(builder, loc, base, change.word);
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
    LLVM::StoreOp::create(builder, loc, next,
                          ownerWordAddress(builder, loc, base, word), 8);
  for (unsigned level = 1; level != layout.levels && !added.empty(); ++level) {
    std::map<unsigned, Value> parents, parentAdded;
    for (auto [child, nonzero] : added) {
      unsigned parent = child / 64;
      Value previous = parents.count(parent)
                           ? parents.at(parent)
                           : loadOwnerWord(builder, loc, base,
                                           layout.offsets[level] + parent);
      Value bit = builder.createOrFold<arith::SelectOp>(
          loc, nonzero,
          llvmConstant(builder, loc, i64, uint64_t{1} << (child % 64)),
          llvmConstant(builder, loc, i64, 0));
      parents[parent] = builder.createOrFold<arith::OrIOp>(loc, previous, bit);
      Value &any = parentAdded[parent];
      any =
          any ? builder.createOrFold<arith::OrIOp>(loc, any, nonzero) : nonzero;
    }
    for (auto [parent, next] : parents)
      LLVM::StoreOp::create(
          builder, loc, next,
          ownerWordAddress(builder, loc, base, layout.offsets[level] + parent),
          8);
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

// Add the words of `mask`, selected by `condition` when given, to the owner
// words at `base`, or remove them with `clear`.
inline void updateOwnerMask(mlir::OpBuilder &builder, mlir::Location loc,
                            mlir::Value base, const llvm::APInt &mask,
                            bool clear = false, mlir::Value condition = {}) {
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
    updateOwnerWord(builder, loc, base, word, selected, clear);
  }
}

// The same for the words of a generated eval ready set, as ready updates.
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

/// The addresses of the ready sets that lowered ready actions access, as
/// canonicalization leaves them: one per set and function, at the start of
/// its entry block. An address the function already has there is reused.
class ReadySetAddresses {
public:
  mlir::Value get(mlir::Operation *user, mlir::FlatSymbolRefAttr set) {
    mlir::Region *body =
        &user->getParentWithTrait<mlir::OpTrait::IsIsolatedFromAbove>()
             ->getRegion(0);
    auto [found, inserted] = addresses.try_emplace({body, set.getAttr()});
    if (!inserted)
      return found->second;
    mlir::Block &entry = body->front();
    for (mlir::Operation &operation : entry) {
      if (!operation.hasTrait<mlir::OpTrait::ConstantLike>())
        break;
      auto address = mlir::dyn_cast<mlir::LLVM::AddressOfOp>(operation);
      if (address && address.getGlobalNameAttr() == set)
        return found->second = address;
    }
    auto builder = mlir::OpBuilder::atBlockBegin(&entry);
    return found->second = mlir::LLVM::AddressOfOp::create(
               builder, user->getLoc(),
               mlir::LLVM::LLVMPointerType::get(user->getContext()),
               set.getValue());
  }

private:
  llvm::DenseMap<std::pair<mlir::Region *, mlir::StringAttr>, mlir::Value>
      addresses;
};

} // namespace talos::detail
#endif
