//===- SimulationNBAStaticPublication.cpp - Static NBA action lists
//--------===//

#include "SimulationAOTPlanning.h"
#include "SimulationEvalNBAQueue.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/Transforms/InlinerInterfaceImpl.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

using namespace mlir;

namespace talos::detail {

void materializeNativeNBAStaticPublication(
    ModuleOp module, LLVM::LLVMFuncOp source, Block *publicationEntry,
    ArrayRef<NativeNBAPublicationAction> actions,
    const NativeNBAStaticPublicationPlan &plan) {
  auto loc = source.getLoc();
  OpBuilder b(source);
  auto declaration =
      module.lookupSymbol<LLVM::LLVMFuncOp>(staticNBAPublicationName);
  assert(declaration && declaration.isExternal());
  auto functionType = declaration.getFunctionType();
  declaration.erase();
  auto empty = [&] {
    b.setInsertionPointAfter(source);
    auto function = LLVM::LLVMFuncOp::create(b, loc, staticNBAPublicationName,
                                             functionType);
    function.setLinkage(LLVM::Linkage::Internal);
    b.setInsertionPointToStart(function.addEntryBlock(b));
    LLVM::ReturnOp::create(b, loc, llvmConstant(b, loc, b.getI1Type(), 0));
  };
  if (plan.slotRoots.empty() &&
      llvm::all_of(plan.scalarRoots, [](uint64_t bits) { return !bits; })) {
    empty();
    return;
  }

  // Reuse the typed consumer emitter, including its unknown-plane and proof
  // publications. Clone before the ordinary barrier chooses table dispatch.
  // The clone has only constant root actions: ordered records are not part of
  // this certificate and must remain owned by the full commit on rejection.
  IRMapping mapping;
  b.setInsertionPointAfter(source);
  auto function = cast<LLVM::LLVMFuncOp>(b.clone(*source, mapping));
  function.setSymName(staticNBAPublicationName);
  function.setLinkage(LLVM::Linkage::Internal);
  function.setFunctionType(functionType);
  for (const auto &action : actions) {
    bool admitted = action.scalar ? (plan.scalarRoots[action.root / 64] &
                                     (uint64_t{1} << (action.root % 64))) != 0
                                  : plan.slotRoots.contains(action.root);
    if (admitted)
      continue;
    auto *branch = mapping.lookup(action.branch);
    b.setInsertionPoint(branch);
    cf::BranchOp::create(b, loc, mapping.lookup(action.next));
    branch->erase();
  }
  Block &entry = function.getBody().front();
  Block *initialize = entry.splitBlock(entry.begin());
  // Keep static stack allocations in the function entry for LLVM's inliner,
  // but initialize publication scratch only after acceptance. Rejected
  // batches must not pay for clearing the full consumer bitmap twice.
  for (auto alloca :
       llvm::make_early_inc_range(initialize->getOps<LLVM::AllocaOp>())) {
    auto *count = alloca.getArraySize().getDefiningOp();
    assert(count && isa<LLVM::ConstantOp>(count) &&
           "publication scratch has a constant allocation size");
    if (count->getBlock() == initialize)
      count->moveBefore(&entry, entry.end());
    alloca->moveBefore(&entry, entry.end());
  }
  auto *oldBranch = initialize->getTerminator();
  b.setInsertionPoint(oldBranch);
  cf::BranchOp::create(b, loc, mapping.lookup(publicationEntry));
  oldBranch->erase();
  b.setInsertionPointToEnd(&entry);
  Value blocked = llvmConstant(b, loc, b.getI64Type(), 0);
  auto include = [&](Value value) {
    blocked = arith::OrIOp::create(b, loc, blocked, value);
  };
  auto pointer = LLVM::LLVMPointerType::get(b.getContext());
  Value dirty = LLVM::AddressOfOp::create(b, loc, pointer,
                                          "__talos_aot_nba_dirty_roots_v1");
  for (auto [word, mask] : llvm::enumerate(plan.scalarRoots)) {
    if (mask == UINT64_MAX)
      continue;
    Value pending = LLVM::LoadOp::create(b, loc, b.getI64Type(),
                                         byteGEP(b, loc, dirty, word * 8), 8);
    include(arith::AndIOp::create(b, loc, pending,
                                  llvmConstant(b, loc, b.getI64Type(), ~mask)));
  }
  // Fixed slots have their own valid words and do not necessarily set dirty
  // root bits. The one-bit dynamic summary cannot prove set membership.
  for (const auto &name : plan.rejectedSlots) {
    Value pending = LLVM::LoadOp::create(
        b, loc, b.getI32Type(),
        LLVM::AddressOfOp::create(b, loc, pointer, name), 4);
    include(arith::ExtUIOp::create(b, loc, b.getI64Type(), pending));
  }
  if (plan.hasOrdered) {
    include(arith::ExtUIOp::create(b, loc, b.getI64Type(),
                                   evalNBAQueueSize(b, loc)));
    Value error = LLVM::LoadOp::create(b, loc, b.getI32Type(),
                                       evalNBAQueueField(b, loc, 3), 4);
    include(arith::ExtUIOp::create(b, loc, b.getI64Type(), error));
  }
  Value wrongRegion = arith::CmpIOp::create(
      b, loc, arith::CmpIPredicate::ne, entry.getArgument(2),
      llvmConstant(b, loc, b.getI32Type(), TALOS_RT_REGION_NBA));
  include(arith::ExtUIOp::create(b, loc, b.getI64Type(), wrongRegion));
  auto *declined = new Block;
  function.getBody().push_back(declined);
  Value accepted =
      arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, blocked,
                            llvmConstant(b, loc, b.getI64Type(), 0));
  cf::CondBranchOp::create(b, loc, accepted, initialize, declined);
  b.setInsertionPointToStart(declined);
  LLVM::ReturnOp::create(b, loc, llvmConstant(b, loc, b.getI1Type(), 0));
  IRRewriter rewriter(b.getContext());
  (void)eraseUnreachableBlocks(rewriter, function.getBody());

  // The remaining region is non-suspending and infallible. A publication
  // needing any runtime error/ownership handoff stays on the original route.
  SmallVector<LLVM::ReturnOp> returns;
  bool infallible = true;
  function.walk([&](LLVM::ReturnOp ret) {
    if (ret->getBlock() == declined)
      return;
    auto status = ret.getArg().getDefiningOp<LLVM::ConstantOp>();
    infallible &= status && isa<IntegerAttr>(status.getValue()) &&
                  cast<IntegerAttr>(status.getValue()).getInt() == TALOS_RT_OK;
    returns.push_back(ret);
  });
  if (!infallible) {
    function.erase();
    empty();
    return;
  }
  for (auto ret : returns) {
    b.setInsertionPoint(ret);
    ret.getArgMutable().assign(llvmConstant(b, loc, b.getI1Type(), 1));
  }
}

LogicalResult inlineNativeNBAStaticPublications(ModuleOp module) {
  DialectRegistry registry;
  LLVM::registerInlinerInterface(registry);
  module.getContext()->appendDialectRegistry(registry);
  InlinerInterface interface(module.getContext());
  SmallVector<LLVM::CallOp> calls;
  module.walk([&](LLVM::CallOp call) {
    if (schedule::has<schedule::Field::EvalStaticNBAPublication>(call))
      calls.push_back(call);
  });
  for (auto call : calls) {
    auto function =
        call.getCallee()
            ? module.lookupSymbol<LLVM::LLVMFuncOp>(*call.getCallee())
            : LLVM::LLVMFuncOp{};
    if (function)
      function->removeAttr("passthrough");
    auto clone = [](OpBuilder &, Region *source, Block *inlineBlock,
                    Block *postInsertBlock, IRMapping &mapping, bool clone) {
      assert(clone && "publication variants remain available to other cuts");
      source->cloneInto(inlineBlock->getParent(),
                        postInsertBlock->getIterator(), mapping);
    };
    if (!function || function.isExternal() ||
        failed(inlineCall(interface, clone, cast<CallOpInterface>(*call),
                          cast<CallableOpInterface>(*function),
                          &function.getBody())))
      return call.emitError("cannot inline certified NBA publication");
    call.erase();
  }
  return success();
}

} // namespace talos::detail
