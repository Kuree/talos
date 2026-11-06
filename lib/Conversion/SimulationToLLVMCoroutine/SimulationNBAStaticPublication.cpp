//===- SimulationNBAStaticPublication.cpp - Static NBA action lists
//--------===//

#include "SimulationAOTPlanning.h"
#include "SimulationEvalNBAQueue.h"
#include "SimulationNativeInlineCost.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/Transforms/InlinerInterfaceImpl.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/STLExtras.h"
#include <optional>

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
  auto *oldBranch = entry.getTerminator();
  b.setInsertionPoint(oldBranch);
  cf::BranchOp::create(b, loc, mapping.lookup(publicationEntry));
  oldBranch->erase();
  IRRewriter rewriter(b.getContext());
  (void)eraseUnreachableBlocks(rewriter, function.getBody());

  // The remaining region is non-suspending and infallible. A publication
  // needing any runtime error/ownership handoff stays on the original route.
  SmallVector<LLVM::ReturnOp> returns;
  bool infallible = true;
  function.walk([&](LLVM::ReturnOp ret) {
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
  // The guard has no publication frame or writes. It can remain in the
  // coordinator while an oversized publication body stays out of line.
  b.setInsertionPointAfter(function);
  auto query = LLVM::LLVMFuncOp::create(b, loc, staticNBAPublicationGuardName,
                                        functionType);
  query.setLinkage(LLVM::Linkage::Internal);
  Block *guardEntry = query.addEntryBlock(b);
  b.setInsertionPointToStart(guardEntry);
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
      b, loc, arith::CmpIPredicate::ne, guardEntry->getArgument(2),
      llvmConstant(b, loc, b.getI32Type(), TALOS_RT_REGION_NBA));
  include(arith::ExtUIOp::create(b, loc, b.getI64Type(), wrongRegion));
  Value accepted =
      arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, blocked,
                            llvmConstant(b, loc, b.getI64Type(), 0));
  LLVM::ReturnOp::create(b, loc, accepted);
}

namespace {

std::optional<bool> constantPublicationResult(LLVM::LLVMFuncOp function) {
  if (!llvm::hasSingleElement(function.getBody()))
    return std::nullopt;
  auto ret =
      dyn_cast<LLVM::ReturnOp>(function.getBody().front().getTerminator());
  APInt value;
  if (!ret || !matchPattern(ret.getArg(), m_ConstantInt(&value)))
    return std::nullopt;
  for (Operation &operation : function.getBody().front())
    if (!isa<LLVM::ConstantOp, LLVM::ZeroOp, LLVM::ReturnOp>(operation))
      return std::nullopt;
  return !value.isZero();
}

LogicalResult inlineEligibilityQuery(InlinerInterface &interface,
                                     LLVM::CallOp call,
                                     LLVM::LLVMFuncOp function) {
  auto clone = [](OpBuilder &, Region *source, Block *inlineBlock,
                  Block *postInsertBlock, IRMapping &mapping, bool clone) {
    assert(clone && "eligibility queries remain available to other cuts");
    source->cloneInto(inlineBlock->getParent(), postInsertBlock->getIterator(),
                      mapping);
  };
  LogicalResult result =
      inlineCall(interface, clone, cast<CallOpInterface>(*call),
                 cast<CallableOpInterface>(*function), &function.getBody());
  if (succeeded(result))
    call.erase();
  return result;
}

} // namespace

LogicalResult materializeNativeNBAStaticPublicationCalls(ModuleOp module) {
  DialectRegistry registry;
  LLVM::registerInlinerInterface(registry);
  module.getContext()->appendDialectRegistry(registry);
  InlinerInterface interface(module.getContext());
  SmallVector<LLVM::CallOp> calls;
  SmallVector<LLVM::LLVMFuncOp> callers;
  module.walk([&](LLVM::CallOp call) {
    if (schedule::has<schedule::Field::EvalStaticNBAPublication>(call))
      calls.push_back(call);
  });
  uint64_t limit = schedule::getMaxInlineOperations(module);
  auto query =
      module.lookupSymbol<LLVM::LLVMFuncOp>(staticNBAPublicationGuardName);
  for (auto call : calls) {
    auto function =
        call.getCallee()
            ? module.lookupSymbol<LLVM::LLVMFuncOp>(*call.getCallee())
            : LLVM::LLVMFuncOp{};
    auto caller = call->getParentOfType<LLVM::LLVMFuncOp>();
    if (!function || function.isExternal() || !caller)
      return call.emitError("static NBA publication requires a defined callee");
    if (!llvm::is_contained(callers, caller))
      callers.push_back(caller);
    schedule::remove<schedule::Field::EvalStaticNBAPublication>(call);
    OpBuilder b(call);
    auto replaceWithConstant = [&](bool value) {
      call.getResult().replaceAllUsesWith(
          llvmConstant(b, call.getLoc(), b.getI1Type(), value));
      call.erase();
    };
    // A missing source certificate is a constant false attempt, even with a
    // tiny budget. Never turn that compile-time decline into a helper call.
    if (auto value = constantPublicationResult(function)) {
      replaceWithConstant(*value);
      continue;
    }
    if (!query || query.isExternal())
      return call.emitError("static NBA publication has no eligibility query");
    bool complete = true;
    function.walk([&](LLVM::ReturnOp ret) {
      complete &= matchPattern(ret.getArg(), m_One());
    });
    if (!complete)
      return call.emitError(
          "static NBA publication body must complete its batch");

    // Bound only the read-only guard copies. Leave the publication bodies
    // as ordinary functions so LLVM can use its target-aware inline cost.
    // Charge prior guard copies against the same caller's current size.
    uint64_t callerCost = nativeInlineCost(caller);
    uint64_t guardCost = nativeInlineCost(query);
    auto fits = [&](uint64_t growth) {
      return callerCost <= limit && growth <= limit - callerCost;
    };
    bool admitGuard = fits(guardCost + 8);
    if (native::has<native::DebugTiming>(module))
      llvm::errs() << "talos static NBA guard: caller=" << caller.getSymName()
                   << " size=" << callerCost << " guard=" << guardCost
                   << " limit=" << limit
                   << " decision=" << (admitGuard ? "inline" : "fallback")
                   << '\n';
    if (!admitGuard) {
      replaceWithConstant(false);
      continue;
    }

    // Keep rejection in the caller. Only accepted batches enter the large
    // publication frame, and neither branch replays an Active producer.
    Location loc = call.getLoc();
    Block *before = call->getBlock();
    Block *done = before->splitBlock(call->getIterator());
    Value outcome = done->addArgument(b.getI1Type(), loc);
    call.getResult().replaceAllUsesWith(outcome);
    auto *publish = new Block;
    done->getParent()->getBlocks().insert(Region::iterator(done), publish);
    call->moveBefore(publish, publish->end());
    b.setInsertionPointToEnd(before);
    auto allowed = LLVM::CallOp::create(
        b, loc, TypeRange{b.getI1Type()},
        SymbolRefAttr::get(module.getContext(), staticNBAPublicationGuardName),
        call.getArgOperands());
    LLVM::CondBrOp::create(
        b, loc, allowed.getResult(), publish, ValueRange{}, done,
        ValueRange{llvmConstant(b, loc, b.getI1Type(), false)});
    b.setInsertionPointToEnd(publish);
    LLVM::BrOp::create(b, loc, ValueRange{call.getResult()}, done);
    if (failed(inlineEligibilityQuery(interface, allowed, query)))
      return failure();
  }
  if (native::has<native::DebugTiming>(module))
    for (auto caller : callers)
      llvm::errs() << "talos static NBA guards complete: caller="
                   << caller.getSymName()
                   << " size=" << nativeInlineCost(caller) << " limit=" << limit
                   << '\n';
  return success();
}

} // namespace talos::detail
