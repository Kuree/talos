//===- WideIntegerVectorization.h - Bound wide shift vectorization --------===//

#ifndef TALOS_LLVM_WIDEINTEGERVECTORIZATION_H
#define TALOS_LLVM_WIDEINTEGERVECTORIZATION_H

#include "llvm/IR/PassManager.h"

namespace talos {

/// Keep loops with variable shifts wider than 128 bits scalar. LLVM's
/// vectorizer can underestimate their legalization cost and create vectors of
/// multi-kilobit integers, making instruction selection and scheduling explode.
///
/// SLP has the same problem with a reduction chain of integers wider than any
/// vector register: it forms up to <32 x iN> whatever N is. Its only
/// per-function control is noimplicitfloat, so this pass also sets that
/// attribute on a function with such a chain, marked so
/// RestoreWideIntegerCodegenPass can remove it before code generation.
struct LimitWideIntegerVectorizationPass
    : llvm::PassInfoMixin<LimitWideIntegerVectorizationPass> {
  llvm::PreservedAnalyses run(llvm::Function &function,
                              llvm::FunctionAnalysisManager &analyses);
};

/// Assemble a wide integer built from narrow fields, `or (shl (zext x), c),
/// ...`, one 64-bit word at a time, as a vector of those words. Legalizing each
/// field of a multi-kilobit integer takes time superlinear in its width, so a
/// packed net with hundreds of drivers would otherwise dominate compilation.
/// The words are native values the vectorizers can use.
struct AssembleWideIntegerWordsPass
    : llvm::PassInfoMixin<AssembleWideIntegerWordsPass> {
  llvm::PreservedAnalyses run(llvm::Function &function,
                              llvm::FunctionAnalysisManager &analyses);
};

/// Undoes the temporary noimplicitfloat once the vectorizers have run, so the
/// target may again use vector registers for implicit copies.
struct RestoreWideIntegerCodegenPass
    : llvm::PassInfoMixin<RestoreWideIntegerCodegenPass> {
  llvm::PreservedAnalyses run(llvm::Function &function,
                              llvm::FunctionAnalysisManager &analyses);
};

} // namespace talos

#endif // TALOS_LLVM_WIDEINTEGERVECTORIZATION_H
