//===- FunctionRoles.h - Generated function roles in LLVM IR ----*- C++ -*-===//
//
// Native function finalization exports the `schedule.eval.role` roles that the
// LLVM passes in this directory read as string function attributes. LLVM
// keeps them on every function it clones or splits from one, as the roles'
// origin semantics require.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_LLVM_FUNCTIONROLES_H
#define TALOS_LLVM_FUNCTIONROLES_H

#include "llvm/ADT/StringRef.h"
#include "llvm/IR/Module.h"

namespace talos {

/// The function holds code of a fused clocked kernel.
inline constexpr llvm::StringLiteral kClockedKernelFnAttr =
    "schedule.clocked_kernel";
/// The function is a generated eval activation body.
inline constexpr llvm::StringLiteral kEvalBodyFnAttr = "schedule.eval_body";

/// Drops the role attributes from bitcode handed to the linker. No pass the
/// linker runs reads them, and they would change the ThinLTO module hash that
/// names promoted local symbols.
inline void dropFunctionRoleAttributes(llvm::Module &module) {
  for (llvm::Function &function : module) {
    function.removeFnAttr(kClockedKernelFnAttr);
    function.removeFnAttr(kEvalBodyFnAttr);
  }
}

} // namespace talos

#endif // TALOS_LLVM_FUNCTIONROLES_H
