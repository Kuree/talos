//===- ClockedKernelOutlining.h - Bound native clocked update bodies ------===//

#ifndef TALOS_LLVM_CLOCKEDKERNELOUTLINING_H
#define TALOS_LLVM_CLOCKEDKERNELOUTLINING_H

#include "llvm/ADT/StringRef.h"
#include "llvm/IR/PassManager.h"

namespace talos {

inline constexpr llvm::StringLiteral kClockedUpdateGroupAttr =
    "talos.clocked-update-group";
inline constexpr unsigned kClockedKernelOutlineTargetSize = 2048;
inline constexpr unsigned kClockedUpdateGroupMaxDAGSize =
    4 * kClockedKernelOutlineTargetSize;

/// Split oversized clocked eval bodies after scalar optimization. Only extract
/// groups with at most six native scalar/pointer inputs and no live SSA
/// outputs. Recreate constant addresses, preserve storage assumptions, and
/// simplify the helpers independently. Pass sampled scalar inputs without
/// loading their source state again.
struct ClockedKernelOutliningPass
    : llvm::PassInfoMixin<ClockedKernelOutliningPass> {
  explicit ClockedKernelOutliningPass(
      unsigned targetSize = kClockedKernelOutlineTargetSize)
      : targetSize(targetSize) {}

  llvm::PreservedAnalyses run(llvm::Module &module,
                              llvm::ModuleAnalysisManager &analyses);

private:
  unsigned targetSize;
};

} // namespace talos

#endif // TALOS_LLVM_CLOCKEDKERNELOUTLINING_H
