//===- Passes.td - Dialect-independent optimization passes --*- tablegen -*-===//

#ifndef TALOS_TRANSFORMS_PASSES
#define TALOS_TRANSFORMS_PASSES

include "mlir/Pass/PassBase.td"

def TalosThreadConstantBranchesPass
    : Pass<"talos-thread-constant-branches"> {
  let summary = "Branch past blocks that only test constant block arguments";
  let description = [{
    A predicate answered on several paths merges its answers in block
    arguments. When a block holds nothing but a branch whose operands are its
    arguments or values defined elsewhere, every incoming edge whose operands
    decide the branch goes straight to the chosen successor, with that
    successor's operands taken from the edge. A block every edge bypasses is
    left unreachable for the canonicalizer. Works on any terminator that
    implements `BranchOpInterface::getSuccessorForOperands`, and on
    `llvm.cond_br`.
  }];
  let dependentDialects = ["mlir::LLVM::LLVMDialect"];
}

#endif // TALOS_TRANSFORMS_PASSES
