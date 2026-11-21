//===- ClockedGuardLayout.cpp - Event-guard arms of clocked kernels
//--------===//

#include "talos/LLVM/ClockedGuardLayout.h"
#include "talos/LLVM/ClockedKernelOutlining.h"
#include "talos/LLVM/FunctionRoles.h"
#include "talos/LLVM/WideIntegerVectorization.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/PostDominators.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/MDBuilder.h"
#include "llvm/IR/Module.h"
#include "llvm/Passes/PassBuilder.h"

using namespace llvm;

namespace talos {

bool ClockedGuardLayoutPass::runOnFunction(Function &function) {
  if (function.isDeclaration() ||
      !function.hasFnAttribute(kClockedKernelFnAttr))
    return false;
  DominatorTree dominance(function);
  PostDominatorTree postDominance(function);
  LoopInfo loops(dominance);
  MDBuilder metadata(function.getContext());
  bool changed = false;
  for (BasicBlock &block : function) {
    auto *branch = dyn_cast<BranchInst>(block.getTerminator());
    if (!branch || !branch->isConditional() ||
        branch->getMetadata(LLVMContext::MD_prof))
      continue;
    BasicBlock *first = branch->getSuccessor(0);
    BasicBlock *second = branch->getSuccessor(1);
    // A loop's back edge is taken on every iteration but the last.
    if (first == second || dominance.dominates(first, &block) ||
        dominance.dominates(second, &block))
      continue;
    // The join is where both paths meet again. When it only returns, the
    // other successor is the rest of the function, not an arm.
    DomTreeNode *node = postDominance.getNode(&block);
    BasicBlock *join =
        node && node->getIDom() ? node->getIDom()->getBlock() : nullptr;
    if (!join || succ_empty(join))
      continue;
    // A join outside the branch's loop makes the branch the loop's exit test:
    // the other successor continues the loop, which is not an arm.
    if (Loop *loop = loops.getLoopFor(&block); loop && !loop->contains(join))
      continue;
    if (join == second)
      branch->setMetadata(LLVMContext::MD_prof,
                          metadata.createBranchWeights(1, 1000));
    else if (join == first)
      branch->setMetadata(LLVMContext::MD_prof,
                          metadata.createBranchWeights(1000, 1));
    else
      continue;
    changed = true;
  }
  return changed;
}

PreservedAnalyses ClockedGuardLayoutPass::run(Module &module,
                                              ModuleAnalysisManager &) {
  for (Function &function : module)
    runOnFunction(function);
  // Metadata only: the CFG and every value are unchanged. Branch probability
  // and frequency analyses read the weights; codegen computes its own.
  return PreservedAnalyses::all();
}

void registerTalosLLVMPasses(PassBuilder &builder) {
  builder.registerVectorizerStartEPCallback(
      [](FunctionPassManager &passes, OptimizationLevel) {
        passes.addPass(AssembleWideIntegerWordsPass());
        passes.addPass(LimitWideIntegerVectorizationPass());
      });
  builder.registerPipelineParsingCallback(
      [](StringRef name, FunctionPassManager &passes,
         ArrayRef<PassBuilder::PipelineElement>) {
        if (name == "talos-print-instruction-selection") {
          passes.addPass(PrintInstructionSelectionPass());
          return true;
        }
        if (name == "talos-limit-wide-integer-vectorization") {
          passes.addPass(LimitWideIntegerVectorizationPass());
          return true;
        }
        if (name == "talos-assemble-wide-integer-words") {
          passes.addPass(AssembleWideIntegerWordsPass());
          return true;
        }
        if (name == "talos-restore-wide-integer-codegen") {
          passes.addPass(RestoreWideIntegerCodegenPass());
          return true;
        }
        return false;
      });
  builder.registerPipelineParsingCallback(
      [](StringRef name, ModulePassManager &passes,
         ArrayRef<PassBuilder::PipelineElement>) {
        if (name.consume_front("talos-outline-clocked-kernels")) {
          unsigned targetSize = kClockedKernelOutlineTargetSize;
          if (!name.empty() &&
              (!name.consume_front("<") || !name.consume_back(">") ||
               name.getAsInteger(10, targetSize) || targetSize < 4 ||
               targetSize > 65536))
            return false;
          passes.addPass(ClockedKernelOutliningPass(targetSize));
          return true;
        }
        if (name != "talos-clocked-guard-layout")
          return false;
        passes.addPass(ClockedGuardLayoutPass());
        return true;
      });
}

} // namespace talos
