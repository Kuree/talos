//===- WideIntegerVectorization.cpp - Bound wide shift vectorization ------===//

#include "talos/LLVM/WideIntegerVectorization.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/PatternMatch.h"
#include "llvm/Transforms/Utils/Local.h"
#include "llvm/Transforms/Utils/LoopUtils.h"

using namespace llvm;
using namespace llvm::PatternMatch;

namespace talos {

namespace {
constexpr StringLiteral wideReductionMarker = "talos-wide-integer-reduction";

/// Up to this width an integer still fits the widest native vector registers,
/// and its legalization cost is modest.
constexpr unsigned maximumNativeBits = 256;

/// SLP reduces a chain of at least this many values.
constexpr unsigned minimumReductionValues = 4;

bool isWideInteger(Type *type) {
  return type->isIntegerTy() && type->getIntegerBitWidth() > maximumNativeBits;
}

/// The values a tree of one associative operation combines, up to `limit`.
unsigned countReductionValues(BinaryOperator *root, unsigned limit) {
  unsigned values = 0;
  SmallVector<Value *> worklist(root->operands());
  while (!worklist.empty() && values < limit) {
    Value *value = worklist.pop_back_val();
    if (auto *inner = dyn_cast<BinaryOperator>(value);
        inner && inner->getOpcode() == root->getOpcode())
      llvm::append_range(worklist, inner->operands());
    else
      ++values;
  }
  return values + worklist.size();
}

/// Whether the function has a chain SLP could turn into a horizontal reduction
/// of integers no vector register holds.
bool hasWideReductionChain(Function &function) {
  for (BasicBlock &block : function)
    for (Instruction &instruction : block) {
      auto *binary = dyn_cast<BinaryOperator>(&instruction);
      if (binary && binary->isAssociative() &&
          isWideInteger(binary->getType()) &&
          countReductionValues(binary, minimumReductionValues) >=
              minimumReductionValues)
        return true;
    }
  return false;
}

/// Bits [offset, offset + width(source)) of the assembled integer.
struct WideField {
  Value *source;
  uint64_t offset;
};

/// Fields below this count cost less to legalize than to assemble by words.
constexpr size_t minimumWideFields = 4;

/// The fields of the single-use `or` tree rooted at `root`, if every leaf is a
/// zero-extended and optionally left-shifted value or a constant.
bool collectWideFields(BinaryOperator *root,
                       SmallVectorImpl<WideField> &fields) {
  SmallVector<Value *> worklist(root->operands());
  while (!worklist.empty()) {
    Value *value = worklist.pop_back_val();
    if (auto *inner = dyn_cast<BinaryOperator>(value);
        inner && inner->getOpcode() == Instruction::Or && inner->hasOneUse()) {
      llvm::append_range(worklist, inner->operands());
      continue;
    }
    if (isa<ConstantInt>(value)) {
      fields.push_back({value, 0});
      continue;
    }
    uint64_t offset = 0;
    if (auto *shift = dyn_cast<BinaryOperator>(value);
        shift && shift->getOpcode() == Instruction::Shl) {
      const APInt *amount = nullptr;
      if (!match(shift->getOperand(1), m_APInt(amount)) ||
          amount->uge(root->getType()->getIntegerBitWidth()))
        return false;
      offset = amount->getZExtValue();
      value = shift->getOperand(0);
    }
    Value *source = nullptr;
    if (!match(value, m_ZExt(m_Value(source))) ||
        !source->getType()->isIntegerTy())
      return false;
    fields.push_back({source, offset});
  }
  return true;
}
} // namespace

PreservedAnalyses AssembleWideIntegerWordsPass::run(Function &function,
                                                    FunctionAnalysisManager &) {
  if (!function.getDataLayout().isLittleEndian())
    return PreservedAnalyses::all();
  SmallVector<BinaryOperator *> roots;
  for (BasicBlock &block : function)
    for (Instruction &instruction : block) {
      auto *binary = dyn_cast<BinaryOperator>(&instruction);
      if (!binary || binary->getOpcode() != Instruction::Or ||
          !isWideInteger(binary->getType()))
        continue;
      // An inner node of a larger single-use tree belongs to that tree's root.
      if (binary->hasOneUse())
        if (auto *user = dyn_cast<BinaryOperator>(binary->user_back());
            user && user->getOpcode() == Instruction::Or)
          continue;
      roots.push_back(binary);
    }
  bool changed = false;
  for (BinaryOperator *root : roots) {
    SmallVector<WideField> fields;
    if (!collectWideFields(root, fields) || fields.size() < minimumWideFields)
      continue;
    const uint64_t bits = root->getType()->getIntegerBitWidth();
    const uint64_t words = (bits + 63) / 64;
    IRBuilder<> builder(root);
    Type *i64 = builder.getInt64Ty();
    SmallVector<Value *> assembled(words, builder.getInt64(0));
    for (const WideField &field : fields) {
      const uint64_t width = field.source->getType()->getIntegerBitWidth();
      const uint64_t last =
          std::min(words - 1, (field.offset + width - 1) / 64);
      for (uint64_t word = field.offset / 64; word <= last; ++word) {
        // The source bit at this word's lowest bit, when the field reaches it.
        const uint64_t start = word * 64;
        Value *piece;
        if (start > field.offset) {
          piece = builder.CreateZExtOrTrunc(
              builder.CreateLShr(field.source, start - field.offset), i64);
        } else {
          piece =
              builder.CreateShl(builder.CreateZExtOrTrunc(field.source, i64),
                                field.offset - start);
        }
        assembled[word] = builder.CreateOr(assembled[word], piece);
      }
    }
    Value *vector = PoisonValue::get(FixedVectorType::get(i64, words));
    for (auto [index, word] : llvm::enumerate(assembled))
      vector = builder.CreateInsertElement(vector, word, index);
    Value *whole = builder.CreateBitCast(vector, builder.getIntNTy(words * 64));
    root->replaceAllUsesWith(builder.CreateTrunc(whole, root->getType()));
    RecursivelyDeleteTriviallyDeadInstructions(root);
    changed = true;
  }
  if (!changed)
    return PreservedAnalyses::all();
  PreservedAnalyses preserved;
  preserved.preserveSet<CFGAnalyses>();
  return preserved;
}

PreservedAnalyses LimitWideIntegerVectorizationPass::run(
    Function &function, FunctionAnalysisManager &analyses) {
  if (!function.hasFnAttribute(Attribute::NoImplicitFloat) &&
      hasWideReductionChain(function)) {
    function.addFnAttr(Attribute::NoImplicitFloat);
    function.addFnAttr(wideReductionMarker);
  }
  LoopInfo &loops = analyses.getResult<LoopAnalysis>(function);
  for (Loop *loop : loops.getLoopsInPreorder()) {
    bool wideShift = false;
    for (BasicBlock *block : loop->blocks()) {
      for (Instruction &instruction : *block) {
        if (instruction.isShift() &&
            instruction.getType()->isIntegerTy() &&
            instruction.getType()->getIntegerBitWidth() > 128 &&
            !isa<ConstantInt>(instruction.getOperand(1))) {
          wideShift = true;
          break;
        }
      }
      if (wideShift)
        break;
    }
    if (wideShift)
      addStringMetadataToLoop(loop, "llvm.loop.vectorize.enable", 0);
  }
  // Only hints change; every analysis of the CFG and values stays valid.
  return PreservedAnalyses::all();
}

PreservedAnalyses
RestoreWideIntegerCodegenPass::run(Function &function,
                                   FunctionAnalysisManager &) {
  if (function.hasFnAttribute(wideReductionMarker)) {
    function.removeFnAttr(Attribute::NoImplicitFloat);
    function.removeFnAttr(wideReductionMarker);
  }
  return PreservedAnalyses::all();
}

} // namespace talos
