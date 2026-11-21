//===- SimulationGroupDataflow.cpp - Group dataflow candidates ------------===//

#include "SimulationNativeInlineCost.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "mlir/IR/Dominance.h"
#include "mlir/Transforms/Mem2Reg.h"
#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;

namespace talos::detail {

/// Prove a finite computation for a dataflow candidate and keep its CFG.
///
/// A member body runs only when one of its inputs changed, and its update and
/// X/Z arms are rare in a well-behaved design. Predicating every member and
/// every arm into straight-line selects would execute those rare paths on
/// each activation, so the candidate keeps the members' branches. Every
/// memory access, branch and publication stays where the member body has it,
/// including untouched X/Z bits in neighboring bytes (IEEE 1800-2023 4.3,
/// 4.6, 6.3.1, 9.4.2). The caller installs the group's two-state certificate
/// guard and keeps the ordinary per-member executor when that certificate
/// fails.
bool materializeNativeGroupDataflow(LLVM::LLVMFuncOp function,
                                    uint64_t budget) {
  // Publication lowering can leave unused context loads, and native lowering
  // private integer temporaries in stack slots. Promote only allocations
  // whose complete use/alias proof the standard memory-slot interfaces
  // establish; an escaping pointer stays a boundary.
  IRRewriter rewriter(function.getContext());
  SmallVector<PromotableAllocationOpInterface> allocations;
  function.walk([&](LLVM::AllocaOp allocation) {
    allocations.push_back(
        cast<PromotableAllocationOpInterface>(allocation.getOperation()));
  });
  if (!allocations.empty() &&
      function.getBody().getBlocks().size() <= budget / allocations.size()) {
    DominanceInfo dominance(function);
    (void)tryToPromoteMemorySlots(allocations, rewriter,
                                  DataLayout::closest(function), dominance);
  }
  (void)runRegionDCE(rewriter, function->getRegions());
  auto reject = [&](StringRef reason, Operation *operation = nullptr) {
    if (native::has<native::DebugTiming>(
            function->getParentOfType<ModuleOp>())) {
      llvm::errs() << "talos group dataflow rejected: " << function.getSymName()
                   << " " << reason;
      if (operation)
        llvm::errs() << " (" << *operation << ")";
      llvm::errs() << '\n';
    }
    return false;
  };
  if (!::talos::schedule::has<::talos::schedule::Field::EvalGroupIngress>(
          function) ||
      function.empty())
    return false;

  DenseMap<Block *, unsigned> indegree;
  uint64_t originalOperations = nativeReadySetAddressCost(function);
  for (Block &block : function.getBody()) {
    indegree.try_emplace(&block, 0);
    if (&block != &function.getBody().front())
      for (BlockArgument arg : block.getArguments())
        if (!isa<IntegerType>(arg.getType()))
          return false;
    for (Operation &operation : block) {
      originalOperations += nativeLoweredSize(&operation);
      if (operation.getNumRegions())
        return false;
      if (auto load = dyn_cast<LLVM::LoadOp>(operation)) {
        if (load.getVolatile_() ||
            load.getOrdering() != LLVM::AtomicOrdering::not_atomic)
          return false;
      } else if (auto store = dyn_cast<LLVM::StoreOp>(operation)) {
        if (store.getVolatile_() ||
            store.getOrdering() != LLVM::AtomicOrdering::not_atomic)
          return false;
      } else if (isa<LLVM::ReturnOp>(operation)) {
        if (operation.getNumOperands())
          return reject("returned value", &operation);
      } else if (isa<LLVM::InvokeOp, LLVM::InlineAsmOp>(operation) ||
                 (operation.hasTrait<OpTrait::IsTerminator>() &&
                  !isa<LLVM::BrOp, LLVM::CondBrOp>(operation))) {
        return reject("unsupported control or effect", &operation);
      }
    }
    for (Block *next : block.getSuccessors())
      ++indegree[next];
  }
  if (originalOperations > budget)
    return reject("operation budget");
  if (indegree[&function.getBody().front()] != 0)
    return false;
  SmallVector<Block *> order{&function.getBody().front()};
  for (size_t i = 0; i < order.size(); ++i)
    for (Block *next : order[i]->getSuccessors())
      if (--indegree[next] == 0)
        order.push_back(next);
  if (order.size() != function.getBody().getBlocks().size())
    return reject("cyclic/unreachable CFG");

  // With an independent group certificate the candidate selects an already
  // proved two-state computation without refreshing member proofs.
  Builder builder(function.getContext());
  schedule::set<schedule::Field::EvalControlFlowDataflow>(
      function, builder.getUnitAttr());
  if (!schedule::has<schedule::Field::EvalGroupProofDomain>(function))
    schedule::set<schedule::Field::EvalRefreshGroupProofs>(
        function, builder.getUnitAttr());
  return true;
}

} // namespace talos::detail
