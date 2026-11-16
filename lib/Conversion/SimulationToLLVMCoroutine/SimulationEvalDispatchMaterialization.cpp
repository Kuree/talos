//===- SimulationEvalDispatchMaterialization.cpp ----------------------===//

#include "SimulationAOTPlanning.h"
#include "SimulationEvalNBAQueue.h"
#include "SimulationEvalReadySet.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"

#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"

#include <map>

using namespace mlir;

namespace talos::detail {
namespace {

constexpr StringLiteral evalFastNBARootsName = "__talos_eval_fast_nba_roots_v1";
constexpr StringLiteral promotionPendingMaskName =
    "__talos_eval_promotion_pending_mask_v1";
constexpr StringLiteral periodicTerminationName =
    "__talos_periodic_termination_v1";
constexpr StringLiteral nbaDirtyRootsName = "__talos_aot_nba_dirty_roots_v1";
constexpr StringLiteral nbaKnownName = "__talos_eval_nba_known_v1";
constexpr StringLiteral evalFourStateNBAHandoffName =
    "__talos_eval_four_state_nba_handoff_v1";
constexpr StringLiteral writeRootsGuardName =
    "talos_rt_v1_static_specialization_guard_roots";
constexpr StringLiteral evalWriteRootsGuardName =
    "__talos_eval_write_guard_roots_v1";

} // namespace

// The held set's layout: a ready-set layout depends only on its leaf count,
// and its storage size grows strictly with it.
static EvalReadySetLayout heldWakeLayout(LLVM::GlobalOp held) {
  uint64_t storage =
      cast<LLVM::LLVMArrayType>(held.getGlobalType()).getNumElements();
  for (uint64_t leaves = 1; leaves <= storage; ++leaves) {
    EvalReadySetLayout layout(static_cast<uint32_t>(leaves * 64));
    if (layout.storageWords == storage)
      return layout;
  }
  llvm_unreachable("held wake set without a ready-set layout");
}

// The merge itself, emitted once per module: callers test the held set first,
// so it runs only when an early NBA update published a wake.
static LLVM::LLVMFuncOp
getOrCreateNBAHeldWakeMerge(ModuleOp module, ArrayRef<int32_t> words,
                            const EvalReadySetLayout &layout, Location loc) {
  if (auto existing =
          module.lookupSymbol<LLVM::LLVMFuncOp>(evalNBAHeldMergeName))
    return existing;
  OpBuilder builder = OpBuilder::atBlockEnd(module.getBody());
  MLIRContext *context = module.getContext();
  auto function = LLVM::LLVMFuncOp::create(
      builder, loc, evalNBAHeldMergeName,
      LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(context), {}),
      LLVM::Linkage::Internal);
  Region *region = &function.getBody();
  auto newBlock = [&] {
    Block *block = new Block;
    region->push_back(block);
    return block;
  };
  builder.setInsertionPointToStart(newBlock());
  Type i64 = builder.getI64Type();
  Type pointer = LLVM::LLVMPointerType::get(context);
  auto constant = [&](uint64_t value) {
    return llvmConstant(builder, loc, i64, value);
  };
  Value held =
      LLVM::AddressOfOp::create(builder, loc, pointer, evalNBAHeldWakesName);
  Value ingress =
      LLVM::AddressOfOp::create(builder, loc, pointer, evalModelIngressName);
  auto word = [&](Value base, uint64_t index) {
    return ownerWordAddress(builder, loc, base, index);
  };
  auto load = [&](Value address) -> Value {
    return LLVM::LoadOp::create(builder, loc, i64, address, 8);
  };
  auto store = [&](Value value, Value address) {
    LLVM::StoreOp::create(builder, loc, value, address, 8);
  };
  // Move one word: OR it into the same ingress word, then clear it. Dirty
  // words move the same way: a held dirty bit covers a held word that the
  // merge may make nonempty in the ingress set, whose dirty bit it then sets.
  auto move = [&](Value heldAddress, Value ingressAddress) {
    Value value = load(heldAddress);
    store(arith::OrIOp::create(builder, loc, load(ingressAddress), value),
          ingressAddress);
    store(constant(0), heldAddress);
  };
  if (!layout.hasSummaries()) {
    for (int32_t index : words)
      move(word(held, index), word(ingress, index));
  } else {
    // Walk the set bits of each first-level summary word that covers a listed
    // leaf: only the held leaves are touched.
    SmallVector<unsigned> groups;
    for (int32_t index : words)
      if (groups.empty() || groups.back() != unsigned(index) / 64)
        groups.push_back(unsigned(index) / 64);
    for (unsigned group : groups) {
      Value summaryAddress = word(held, layout.offsets[1] + group);
      Value summary = load(summaryAddress);
      Block *visit = newBlock(), *loop = newBlock(), *body = newBlock(),
            *next = newBlock();
      loop->addArgument(i64, loc);
      cf::CondBranchOp::create(
          builder, loc,
          arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne,
                                summary, constant(0)),
          visit, ValueRange{}, next, ValueRange{});
      builder.setInsertionPointToStart(visit);
      move(summaryAddress, word(ingress, layout.offsets[1] + group));
      cf::BranchOp::create(builder, loc, loop, ValueRange{summary});
      builder.setInsertionPointToStart(loop);
      Value bits = loop->getArgument(0);
      cf::CondBranchOp::create(
          builder, loc,
          arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, bits,
                                constant(0)),
          body, ValueRange{}, next, ValueRange{});
      builder.setInsertionPointToStart(body);
      Value leaf = arith::AddIOp::create(
          builder, loc,
          LLVM::CountTrailingZerosOp::create(builder, loc, i64, bits, true),
          constant(uint64_t{group} * 64));
      move(LLVM::GEPOp::create(builder, loc, pointer, i64, held,
                               ValueRange{leaf}),
           LLVM::GEPOp::create(builder, loc, pointer, i64, ingress,
                               ValueRange{leaf}));
      cf::BranchOp::create(
          builder, loc, loop,
          ValueRange{arith::AndIOp::create(
              builder, loc, bits,
              arith::SubIOp::create(builder, loc, bits, constant(1)))});
      builder.setInsertionPointToStart(next);
    }
    for (unsigned level = 2; level != layout.levels; ++level)
      for (unsigned index = 0; index != layout.counts[level]; ++index)
        move(word(held, layout.offsets[level] + index),
             word(ingress, layout.offsets[level] + index));
  }
  LLVM::ReturnOp::create(builder, loc, ValueRange{});
  return function;
}

void emitNBAHeldWakeMerge(OpBuilder &builder, Location loc, ModuleOp module,
                          Block *merged, ValueRange mergedOperands, Block *none,
                          ValueRange noneOperands) {
  auto held = module.lookupSymbol<LLVM::GlobalOp>(evalNBAHeldWakesName);
  DenseI32ArrayAttr words =
      held ? ::talos::schedule::get<::talos::schedule::Field::EvalNbaHeldWords>(
                 held)
           : DenseI32ArrayAttr{};
  if (!words || words.empty()) {
    cf::BranchOp::create(builder, loc, none, noneOperands);
    return;
  }
  EvalReadySetLayout layout = heldWakeLayout(held);
  LLVM::LLVMFuncOp merge =
      getOrCreateNBAHeldWakeMerge(module, words.asArrayRef(), layout, loc);
  Type i64 = builder.getI64Type();
  Value base = LLVM::AddressOfOp::create(
      builder, loc, LLVM::LLVMPointerType::get(builder.getContext()),
      evalNBAHeldWakesName);
  auto load = [&](uint64_t index) -> Value {
    return LLVM::LoadOp::create(builder, loc, i64,
                                ownerWordAddress(builder, loc, base, index), 8);
  };
  // Only the merge consumes the held set, so its top dirty words covering
  // the listed leaves are nonzero exactly when one of them is; a flat layout
  // tests its listed leaves.
  Value pending;
  if (layout.hasSummaries()) {
    unsigned shift = 6 * (layout.levels - 1);
    std::optional<uint32_t> last;
    for (int32_t index : words.asArrayRef()) {
      uint32_t top = uint32_t(index) >> shift;
      if (last == top)
        continue;
      last = top;
      Value bits = load(layout.offsets[layout.levels - 1] + top);
      pending =
          pending ? arith::OrIOp::create(builder, loc, pending, bits) : bits;
    }
  } else {
    pending = llvmConstant(builder, loc, i64, 0);
    for (int32_t index : words.asArrayRef())
      pending = arith::OrIOp::create(builder, loc, pending, load(index));
  }
  Block *call = new Block;
  builder.getInsertionBlock()->getParent()->push_back(call);
  cf::CondBranchOp::create(
      builder, loc,
      arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ne, pending,
                            llvmConstant(builder, loc, i64, 0)),
      call, ValueRange{}, none, noneOperands);
  builder.setInsertionPointToStart(call);
  LLVM::CallOp::create(builder, loc, merge, ValueRange{});
  cf::BranchOp::create(builder, loc, merged, mergedOperands);
}

void releaseNBAHeldWakesBeforeReturns(LLVM::LLVMFuncOp function) {
  auto module = function->getParentOfType<ModuleOp>();
  auto held = module.lookupSymbol<LLVM::GlobalOp>(evalNBAHeldWakesName);
  if (!held || !::talos::schedule::has<
                   ::talos::schedule::Field::EvalNbaHeldWords>(held))
    return;
  SmallVector<LLVM::ReturnOp> returns;
  function.walk([&](LLVM::ReturnOp op) { returns.push_back(op); });
  for (LLVM::ReturnOp op : returns) {
    Block *block = op->getBlock();
    Block *tail = block->splitBlock(op);
    OpBuilder builder = OpBuilder::atBlockEnd(block);
    emitNBAHeldWakeMerge(builder, op.getLoc(), module, tail, ValueRange{},
                         tail, ValueRange{});
  }
}

LogicalResult
materializeNativeEvalDispatch(ModuleOp module,
                              const NativeEvalCoordinatorPlan &plan) {
  StringRef functionName = evalDispatchName;
  ArrayRef<std::string> executors = plan.fourStateExecutors;
  DenseSet<uint32_t> clockedKernelOwners =
      collectClockedKernelOwners(plan.rankedNodes);
  ArrayRef<NativeEvalClockKernel> clockKernels = plan.clockKernels;
  ArrayRef<talos_rt_native_merged_fragment> mergedFragments = plan.fragments;
  ArrayRef<std::string> mergedTwoStateExecutors = plan.twoStateExecutors;
  ArrayRef<APInt> ownerSubsumptionMasks = plan.ownerSubsumptionMasks;
  uint32_t nbaTaintWordCount = plan.nbaTaintWordCount;
  bool prioritySignalHandoff = plan.prioritySignalHandoff;
  unsigned ownerCount = std::max<size_t>(64, mergedFragments.size());
  APInt allOwners = APInt::getAllOnes(ownerCount);
  const EvalReadySetLayout readyLayout(ownerCount);
  APInt allowedOwnerMask = allOwners;
  // A multi-word set runs its Active owners by word sweep (word functions
  // below); a single word keeps per-owner selection.
  const bool sweep = readyLayout.hasSummaries();
  const bool hasDeferred = plan.firstDeferredBit < mergedFragments.size();
  const uint64_t activeBits =
      hasDeferred ? plan.firstDeferredBit : mergedFragments.size();
  auto swept = [&](uint32_t bit) { return sweep && bit < activeBits; };

  MLIRContext *context = module.getContext();
  OpBuilder builder(context);
  Location location = module.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i32 = builder.getI32Type();
  Type i64 = builder.getI64Type();
  auto ownerMayTaintNBA = [&](unsigned owner) {
    return owner < plan.nbaTaintedOwners.size() &&
           plan.nbaTaintedOwners.test(owner);
  };
  auto markOwnerNBATaint = [&](unsigned owner) {
    if (!ownerMayTaintNBA(owner) || nbaTaintWordCount == 0)
      return;
    Value taintBase = LLVM::AddressOfOp::create(builder, location, pointer,
                                                evalStepFourStateNBARootsName);
    for (uint32_t word = 0; word != nbaTaintWordCount; ++word) {
      uint64_t mask = plan.nbaTaintMasks[owner][word];
      if (mask == 0)
        continue;
      Value address = byteGEP(builder, location, taintBase,
                              uint64_t{word} * sizeof(uint64_t));
      Value old = LLVM::LoadOp::create(builder, location, i64, address, 8);
      LLVM::StoreOp::create(
          builder, location,
          arith::OrIOp::create(builder, location, old,
                               llvmConstant(builder, location, i64, mask)),
          address, 8);
    }
  };

  if (clockKernels.empty() || mergedFragments.empty() ||
      executors.size() != mergedFragments.size() ||
      ownerSubsumptionMasks.size() != mergedFragments.size())
    return success();
  // Executor symbols are fixed inputs. The coordinator emitted below is not
  // part of this lookup snapshot, and no executor is added, renamed or erased.
  SymbolTable executorSymbols(module);
  builder.setInsertionPointToEnd(module.getBody());
  if (plan.writableVPI) {
    // IEEE 1800-2023 38.34 and 10.6: a deposit/force invalidates only the
    // affected source dependencies. Keep scheduling and knownness separate;
    // a known forced value still requires override-aware fine execution.
    // One shared cold roots query: native partitions cannot inline
    // thousands of per-owner helpers.
    auto guard = LLVM::LLVMFuncOp::create(
        builder, location, evalWriteRootsGuardName,
        LLVM::LLVMFunctionType::get(builder.getI1Type(),
                                    {pointer, pointer, i64}, false));
    Block *entry = guard.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);
    Value checked =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             writeRootsGuardName, entry->getArguments())
            .getResult();
    Value allowed = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne, checked,
        llvmConstant(builder, location, i32, 0));
    LLVM::ReturnOp::create(builder, location, allowed);
    builder.setInsertionPointAfter(guard);
    for (auto [owner, states] : llvm::enumerate(plan.ownerStaticStates)) {
      if (states.empty())
        continue;
      std::string rootsName =
          "__talos_eval_write_guard_states_" + std::to_string(owner) + "_v1";
      auto array = LLVM::LLVMArrayType::get(i32, states.size());
      auto values = DenseElementsAttr::get(
          RankedTensorType::get({static_cast<int64_t>(states.size())}, i32),
          ArrayRef<uint32_t>(states));
      makeConstantGlobal(module, location, array, rootsName,
                         LLVM::Linkage::Internal, 4, values);
    }
  }
  SmallVector<Type> coordinatorArguments{pointer, pointer};
  auto fastCoordinator = LLVM::LLVMFuncOp::create(
      builder, location, functionName,
      LLVM::LLVMFunctionType::get(i32, coordinatorArguments, false));
  ::talos::schedule::set<schedule::metadata::evalCallClosureRoot>(
      fastCoordinator, builder.getUnitAttr());
  Block *fastEntry = fastCoordinator.addEntryBlock(builder);
  Block *dispatch = new Block;
  Block *commit = new Block;
  Block *performCommit = new Block;
  Block *afterCommit = new Block;
  Block *complete = new Block;
  complete->addArgument(i32, location);
  Block *stopped = new Block;
  Block *failed = new Block;
  failed->addArgument(i32, location);
  fastCoordinator.getBody().push_back(dispatch);
  fastCoordinator.getBody().push_back(commit);
  fastCoordinator.getBody().push_back(performCommit);
  fastCoordinator.getBody().push_back(afterCommit);
  fastCoordinator.getBody().push_back(complete);
  fastCoordinator.getBody().push_back(stopped);
  fastCoordinator.getBody().push_back(failed);
  builder.setInsertionPointToStart(fastEntry);
  Value changed = entryAlloca(builder, location, i32, 1, 4);
  Value fourStateFallback =
      entryAlloca(builder, location, builder.getI1Type(), 1, 1);
  LLVM::StoreOp::create(
      builder, location,
      arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::ne,
          LLVM::LoadOp::create(
              builder, location, builder.getI8Type(),
              LLVM::AddressOfOp::create(builder, location, pointer,
                                        evalStepFourStateFallbackName),
              1),
          llvmConstant(builder, location, builder.getI8Type(), 0))
          .getResult(),
      fourStateFallback, 1);
  // IEEE 1800-2023 4.4.2.3-4.4.2.4, 4.5: deferred (#0) owners run only once
  // the Active region is empty and NBA events only once Active and Inactive
  // are, runtime processes included; the runtime's own NBA events join the
  // same batch, so a commit also waits for them (talos_rt_native_schedule_plan
  // .runtime_yield). At such a cut a runtime scheduler call (yield word
  // ALLOWED) asks whether runtime work below `cutRegion` remains and, if so,
  // returns with its ready bits and NBA staging intact, storing
  // `yieldedWord`; the runtime calls again once that work is done. FIRST_CUT
  // passes one cut without asking. Generated drivers leave the word at
  // COMMIT and pay one load and branch here. The plan's runtime_yield field
  // points at this word (makeNativeEvalPlan).
  auto emitRuntimeCut = [&](uint32_t cutRegion, uint32_t yieldedWord,
                            Block *proceed, ValueRange proceedOperands) {
    constexpr unsigned wordAlignment = alignof(uint32_t);
    if (!module.lookupSymbol(evalRuntimeYieldName)) {
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToStart(module.getBody());
      LLVM::GlobalOp::create(
          builder, location, i32, /*isConstant=*/false, LLVM::Linkage::Internal,
          evalRuntimeYieldName,
          builder.getI32IntegerAttr(TALOS_RT_RUNTIME_YIELD_COMMIT),
          wordAlignment);
    }
    LLVM::LLVMFuncOp runtimeWorkPending = getOrDeclareLLVMFunction(
        module, runtimeWorkPendingName, i32, {pointer, i32});
    Value runtimeContext = fastEntry->getArgument(1);
    Value yieldWord = LLVM::AddressOfOp::create(builder, location, pointer,
                                                evalRuntimeYieldName);
    Value word =
        LLVM::LoadOp::create(builder, location, i32, yieldWord, wordAlignment);
    auto wordIs = [&](uint32_t value) -> Value {
      return arith::CmpIOp::create(builder, location, arith::CmpIPredicate::eq,
                                   word,
                                   llvmConstant(builder, location, i32, value));
    };
    Block *runtimeDriven = new Block, *firstCut = new Block,
          *askRuntime = new Block, *yield = new Block;
    for (Block *block : {runtimeDriven, firstCut, askRuntime, yield})
      fastCoordinator.getBody().push_back(block);
    cf::CondBranchOp::create(builder, location,
                             wordIs(TALOS_RT_RUNTIME_YIELD_COMMIT), proceed,
                             proceedOperands, runtimeDriven, ValueRange{});
    builder.setInsertionPointToStart(runtimeDriven);
    cf::CondBranchOp::create(builder, location,
                             wordIs(TALOS_RT_RUNTIME_YIELD_FIRST_CUT), firstCut,
                             ValueRange{}, askRuntime, ValueRange{});
    builder.setInsertionPointToStart(firstCut);
    LLVM::StoreOp::create(
        builder, location,
        llvmConstant(builder, location, i32, TALOS_RT_RUNTIME_YIELD_ALLOWED),
        yieldWord, wordAlignment);
    cf::BranchOp::create(builder, location, proceed, proceedOperands);
    builder.setInsertionPointToStart(askRuntime);
    Value pending =
        LLVM::CallOp::create(
            builder, location, runtimeWorkPending,
            ValueRange{runtimeContext,
                       llvmConstant(builder, location, i32, cutRegion)})
            .getResult();
    cf::CondBranchOp::create(
        builder, location,
        arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                              pending, llvmConstant(builder, location, i32, 0)),
        yield, ValueRange{}, proceed, proceedOperands);
    builder.setInsertionPointToStart(yield);
    // The call that commits starts from the step's four-state evidence:
    // keep what this call's owners staged (it selects the commit path).
    Value stepFallback = LLVM::AddressOfOp::create(
        builder, location, pointer, evalStepFourStateFallbackName);
    LLVM::StoreOp::create(
        builder, location,
        arith::OrIOp::create(
            builder, location,
            LLVM::LoadOp::create(builder, location, builder.getI8Type(),
                                 stepFallback, 1),
            arith::ExtUIOp::create(builder, location, builder.getI8Type(),
                                   LLVM::LoadOp::create(builder, location,
                                                        builder.getI1Type(),
                                                        fourStateFallback, 1))),
        stepFallback, 1);
    LLVM::StoreOp::create(builder, location,
                          llvmConstant(builder, location, i32, yieldedWord),
                          yieldWord, wordAlignment);
    cf::BranchOp::create(
        builder, location, complete,
        ValueRange{llvmConstant(builder, location, i32, TALOS_RT_OK)});
  };
  auto ingressAddress = [&] {
    return LLVM::AddressOfOp::create(builder, location, pointer,
                                     evalModelIngressName)
        .getResult();
  };
  auto combinedIngress = [&] {
    return maskedOwnerWords(builder, location, ingressAddress(), allOwners);
  };
  auto ownerWritableClean = [&](unsigned owner, Value context) -> Value {
    Value clean = llvmConstant(builder, location, builder.getI1Type(), 1);
    if (plan.writableVPI && !plan.ownerStaticStates[owner].empty()) {
      // Recheck at every owner: an intervening runtime/foreign callback can
      // deposit or force a value and invalidate the fast flag mid-dispatch.
      Region *body = builder.getInsertionBlock()->getParent();
      Block *check = new Block, *join = new Block;
      join->addArgument(builder.getI1Type(), location);
      body->push_back(check);
      body->push_back(join);
      Value fast = LLVM::LoadOp::create(
          builder, location, i32,
          LLVM::AddressOfOp::create(builder, location, pointer,
                                    "__talos_static_specialization_fast_v1"),
          4);
      Value isClean =
          arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                fast, llvmConstant(builder, location, i32, 0));
      cf::CondBranchOp::create(builder, location, isClean, join,
                               ValueRange{clean}, check, ValueRange{});
      builder.setInsertionPointToStart(check);
      std::string rootsName =
          "__talos_eval_write_guard_states_" + std::to_string(owner) + "_v1";
      Value allowed =
          LLVM::CallOp::create(
              builder, location, TypeRange{builder.getI1Type()},
              evalWriteRootsGuardName,
              ValueRange{context,
                         LLVM::AddressOfOp::create(builder, location, pointer,
                                                   rootsName),
                         llvmConstant(builder, location, i64,
                                      plan.ownerStaticStates[owner].size())})
              .getResult();
      cf::BranchOp::create(builder, location, join, ValueRange{allowed});
      builder.setInsertionPointToStart(join);
      clean = join->getArgument(0);
    }
    return clean;
  };
  auto clearIngressMask = [&](const APInt &mask, Value condition = Value{}) {
    updateOwnerMask(builder, location, ingressAddress(), mask,
                    /*clear=*/true, condition, &readyLayout);
  };
  cf::BranchOp::create(builder, location, dispatch);
  builder.setInsertionPointToStart(dispatch);
  if (plan.hasOrderedNBA) {
    Value status = LLVM::LoadOp::create(
        builder, location, i32, evalNBAQueueField(builder, location, 3), 4);
    Value ok = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, status,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    Block *proceed = new Block;
    fastCoordinator.getBody().push_back(proceed);
    cf::CondBranchOp::create(builder, location, ok, proceed, ValueRange{},
                             complete, ValueRange{status});
    builder.setInsertionPointToStart(proceed);
  }
  Block *scanReady = new Block;
  fastCoordinator.getBody().push_back(scanReady);
  if (prioritySignalHandoff) {
    Value prioritySignalPending =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            SymbolRefAttr::get(context,
                               "talos_rt_v1_scheduler_priority_signal_pending"),
            ValueRange{fastEntry->getArgument(1)})
            .getResult();
    Value mustHandoff = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne, prioritySignalPending,
        llvmConstant(builder, location, i32, 0));
    cf::CondBranchOp::create(builder, location, mustHandoff, complete,
                             ValueRange{llvmConstant(builder, location, i32,
                                                     TALOS_RT_AOT_CHECKPOINT)},
                             scanReady, ValueRange{});
  } else {
    cf::BranchOp::create(builder, location, scanReady);
  }

  builder.setInsertionPointToStart(scanReady);
  // Owners at or above firstDeferredBit resume in the Inactive region (IEEE
  // 1800-2023 4.4.2.3). Planning gives them the highest bits, so they run
  // only once no Active owner is pending: this closure is quiescent. With a
  // runtime calendar, runtime-owned Active and Inactive work must also drain
  // first, which the NBA cut below performs.
  bool runtimeCalendar =
      ::talos::schedule::has<::talos::schedule::Field::EvalRuntimeCalendar>(
          module);
  APInt deferredOwnerMask(ownerCount, 0);
  if (hasDeferred)
    deferredOwnerMask.setBits(plan.firstDeferredBit, mergedFragments.size());
  // A finish request ends the simulation before any remaining scheduled
  // event, deferred owners included (IEEE 1800-2023 9.2.3, 20.2). A
  // runtime-calendar coordinator learns it from its NBA cut
  // (TALOS_RT_EVAL_NBA_TERMINATED); the others read the termination latch.
  auto terminationRequested = [&]() -> Value {
    getOrDeclareLLVMFunction(
        module, "talos_rt_v1_scheduler_termination_requested", i32, {pointer});
    Value latch =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             "talos_rt_v1_scheduler_termination_requested",
                             ValueRange{fastEntry->getArgument(1)})
            .getResult();
    return arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                 latch,
                                 llvmConstant(builder, location, i32, 0));
  };
  // Every owner without its own word sweep executes from this switch.
  Block *switchBlock = new Block;
  Value bit = switchBlock->addArgument(i64, location);
  fastCoordinator.getBody().push_back(switchBlock);
  // Enter the deferred owner `selected` once no Active owner is pending.
  auto enterDeferred = [&](Value selected) {
    if (runtimeCalendar) {
      cf::BranchOp::create(builder, location, commit);
      return;
    }
    Block *inactiveCut = new Block;
    fastCoordinator.getBody().push_back(inactiveCut);
    cf::CondBranchOp::create(builder, location, terminationRequested(), stopped,
                             ValueRange{}, inactiveCut, ValueRange{});
    builder.setInsertionPointToStart(inactiveCut);
    emitRuntimeCut(TALOS_RT_REGION_INACTIVE, TALOS_RT_RUNTIME_YIELD_DEFERRED,
                   switchBlock, ValueRange{selected});
  };
  // The word sweep's selection: the lowest dirty word holding Active owners,
  // then its gate. See runtime::DirtyReadySetLayout; a dirty bit only bounds
  // its pending children, so a reader that finds a child without Active work
  // clears the bit and searches again. Blocks are filled in below.
  auto constant = [&](uint64_t value) {
    return llvmConstant(builder, location, i64, value);
  };
  auto ingressWord = [&](Value index, uint64_t offset) -> Value {
    if (offset)
      index = arith::AddIOp::create(builder, location, index, constant(offset));
    return LLVM::GEPOp::create(builder, location, pointer, i64,
                               ingressAddress(), ValueRange{index});
  };
  // Children of the words of `level` that cover Active owners, a prefix of
  // each level: owner bits for level 0, words of level - 1 above it. The
  // flat top level scans activeChildren[levels] words.
  SmallVector<uint64_t> activeChildren(readyLayout.levels + 1);
  activeChildren[0] = activeBits;
  for (unsigned level = 1; level <= readyLayout.levels; ++level)
    activeChildren[level] = (activeChildren[level - 1] + 63) / 64;
  // The Active children of word `index` of `level` (level 0: owner bits).
  // Without deferred owners every child that can be set is Active.
  auto activeMask = [&](unsigned level, Value index) -> Value {
    uint64_t children = activeChildren[level];
    if (!hasDeferred || children % 64 == 0)
      return constant(UINT64_MAX);
    return arith::SelectOp::create(
        builder, location,
        arith::CmpIOp::create(builder, location, arith::CmpIPredicate::eq,
                              index, constant(children / 64)),
        constant((uint64_t{1} << (children % 64)) - 1), constant(UINT64_MAX));
  };
  // Whether a word holding Active owners may be pending. Exact after the
  // sweep found none, until an owner consumes again: every add sets its bits.
  auto newCoordinatorBlock = [&] {
    Block *block = new Block;
    fastCoordinator.getBody().push_back(block);
    return block;
  };
  auto activeDirty = [&]() -> Value {
    unsigned top = readyLayout.levels - 1;
    Value any = constant(0);
    for (uint64_t word = 0; word != activeChildren[top + 1]; ++word) {
      Value bits = loadOwnerWord(builder, location, ingressAddress(),
                                 readyLayout.offsets[top] + word);
      uint64_t children = activeChildren[top] - word * 64;
      if (children < 64)
        bits = arith::AndIOp::create(builder, location, bits,
                                     constant((uint64_t{1} << children) - 1));
      any = arith::OrIOp::create(builder, location, any, bits);
    }
    return any;
  };
  // No Active owner is pending: the lowest pending deferred owner runs next,
  // or the closure is quiescent. A runtime calendar's NBA cut drains the
  // deferred owners itself.
  auto emitActiveEmpty = [&] {
    if (hasDeferred && !runtimeCalendar) {
      for (unsigned word = plan.firstDeferredBit / 64;
           word * 64 < mergedFragments.size(); ++word) {
        Value pending = arith::AndIOp::create(
            builder, location,
            loadOwnerWord(builder, location, ingressAddress(), word),
            constant(ownerMaskWord(deferredOwnerMask, word)));
        Block *execute = newCoordinatorBlock(), *next = newCoordinatorBlock();
        cf::CondBranchOp::create(builder, location,
                                 arith::CmpIOp::create(builder, location,
                                                       arith::CmpIPredicate::ne,
                                                       pending, constant(0)),
                                 execute, ValueRange{}, next, ValueRange{});
        builder.setInsertionPointToStart(execute);
        enterDeferred(
            arith::AddIOp::create(builder, location,
                                  LLVM::CountTrailingZerosOp::create(
                                      builder, location, i64, pending, true),
                                  constant(uint64_t{word} * 64)));
        builder.setInsertionPointToStart(next);
      }
    }
    cf::BranchOp::create(builder, location, commit);
  };
  Block *wordSwitch = nullptr, *afterWord = nullptr;
  if (!sweep) {
    SmallVector<Value> ready;
    for (unsigned word = 0; word != allOwners.getNumWords(); ++word)
      ready.push_back(loadOwnerWord(builder, location, ingressAddress(), word));
    llvm::BitVector changedWords(ready.size());
    for (auto [recordIndex, record] : llvm::enumerate(mergedFragments)) {
      const APInt &subsumed = ownerSubsumptionMasks[recordIndex];
      if (subsumed.isZero() || !allowedOwnerMask[record.bit])
        continue;
      Value coordinatorPending = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::ne,
          arith::AndIOp::create(builder, location, ready[record.bit / 64],
                                llvmConstant(builder, location, i64,
                                             uint64_t{1} << (record.bit % 64))),
          llvmConstant(builder, location, i64, 0));
      if (plan.writableVPI)
        coordinatorPending = arith::AndIOp::create(
            builder, location, coordinatorPending,
            ownerWritableClean(recordIndex, fastEntry->getArgument(1)));
      for (unsigned word = 0; word != ready.size(); ++word) {
        uint64_t members = ownerMaskWord(subsumed, word);
        if (!members)
          continue;
        changedWords.set(word);
        Value withoutMembers = arith::AndIOp::create(
            builder, location, ready[word],
            llvmConstant(builder, location, i64, ~members));
        ready[word] = arith::SelectOp::create(
            builder, location, coordinatorPending, withoutMembers, ready[word]);
      }
    }
    for (int word : changedWords.set_bits())
      LLVM::StoreOp::create(
          builder, location, ready[word],
          ownerWordAddress(builder, location, ingressAddress(), word), 8);
    Value selectedReady = ready.front();
    Value empty = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, selectedReady,
        llvmConstant(builder, location, i64, 0));
    Block *select = new Block;
    fastCoordinator.getBody().push_back(select);
    cf::CondBranchOp::create(builder, location, empty, commit, ValueRange{},
                             select, ValueRange{});
    builder.setInsertionPointToStart(select);
    Value selectedBit = LLVM::CountTrailingZerosOp::create(
        builder, location, i64, selectedReady, true);
    if (hasDeferred) {
      Value isDeferred = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::uge, selectedBit,
          llvmConstant(builder, location, i64, plan.firstDeferredBit));
      Block *deferred = commit;
      if (!runtimeCalendar) {
        deferred = new Block;
        fastCoordinator.getBody().push_back(deferred);
      }
      cf::CondBranchOp::create(builder, location, isDeferred, deferred,
                               ValueRange{}, switchBlock,
                               ValueRange{selectedBit});
      if (!runtimeCalendar) {
        builder.setInsertionPointToStart(deferred);
        enterDeferred(selectedBit);
      }
    } else {
      cf::BranchOp::create(builder, location, switchBlock,
                           ValueRange{selectedBit});
    }
  } else if (activeChildren[readyLayout.levels] == 0) {
    // Every owner is deferred: none is swept.
    emitActiveEmpty();
  } else {
    unsigned top = readyLayout.levels - 1;
    auto newBlock = [&](unsigned arguments = 0) {
      Block *block = new Block;
      for (unsigned i = 0; i != arguments; ++i)
        block->addArgument(i64, location);
      fastCoordinator.getBody().push_back(block);
      return block;
    };
    // clearFrom[level](child): clear child's bit in `level`; continue upward
    // while the word keeps no Active child, then dispatch again.
    SmallVector<Block *> clearFrom(readyLayout.levels, nullptr);
    for (unsigned level = 1; level <= top; ++level)
      clearFrom[level] = newBlock(1);
    for (unsigned level = 1; level <= top; ++level) {
      builder.setInsertionPointToStart(clearFrom[level]);
      Value child = clearFrom[level]->getArgument(0);
      Value parent =
          arith::ShRUIOp::create(builder, location, child, constant(6));
      Value address = ingressWord(parent, readyLayout.offsets[level]);
      Value bit = arith::ShLIOp::create(
          builder, location, constant(1),
          arith::AndIOp::create(builder, location, child, constant(63)));
      Value next = arith::AndIOp::create(
          builder, location,
          LLVM::LoadOp::create(builder, location, i64, address, 8),
          arith::XOrIOp::create(builder, location, bit, constant(UINT64_MAX)));
      LLVM::StoreOp::create(builder, location, next, address, 8);
      if (level == top) {
        cf::BranchOp::create(builder, location, dispatch);
        continue;
      }
      Value kept = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::ne,
          arith::AndIOp::create(builder, location, next,
                                activeMask(level, parent)),
          constant(0));
      cf::CondBranchOp::create(builder, location, kept, dispatch, ValueRange{},
                               clearFrom[level + 1], ValueRange{parent});
    }
    // Scan the flat top level in order, then descend through the lowest
    // dirty bit of each level to a leaf word.
    Block *activeEmpty = newBlock();
    Block *descend = newBlock(1);
    builder.setInsertionPointToStart(scanReady);
    for (uint64_t word = 0; word != activeChildren[top + 1]; ++word) {
      Value bits = loadOwnerWord(builder, location, ingressAddress(),
                                 readyLayout.offsets[top] + word);
      uint64_t children = activeChildren[top] - word * 64;
      if (children < 64)
        bits = arith::AndIOp::create(builder, location, bits,
                                     constant((uint64_t{1} << children) - 1));
      Block *found = newBlock();
      Block *next =
          word + 1 == activeChildren[top + 1] ? activeEmpty : newBlock();
      cf::CondBranchOp::create(builder, location,
                               arith::CmpIOp::create(builder, location,
                                                     arith::CmpIPredicate::ne,
                                                     bits, constant(0)),
                               found, ValueRange{}, next, ValueRange{});
      builder.setInsertionPointToStart(found);
      cf::BranchOp::create(builder, location, descend,
                           ValueRange{arith::AddIOp::create(
                               builder, location,
                               LLVM::CountTrailingZerosOp::create(
                                   builder, location, i64, bits, true),
                               constant(word * 64))});
      builder.setInsertionPointToStart(next);
    }
    builder.setInsertionPointToStart(descend);
    Value child = descend->getArgument(0);
    for (unsigned level = top - 1; level != 0; --level) {
      // `child` names a word of `level`.
      Value bits = arith::AndIOp::create(
          builder, location,
          LLVM::LoadOp::create(builder, location, i64,
                               ingressWord(child, readyLayout.offsets[level]),
                               8),
          activeMask(level, child));
      Block *lower = newBlock();
      cf::CondBranchOp::create(
          builder, location,
          arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                bits, constant(0)),
          lower, ValueRange{}, clearFrom[level + 1], ValueRange{child});
      builder.setInsertionPointToStart(lower);
      child = arith::AddIOp::create(
          builder, location,
          LLVM::CountTrailingZerosOp::create(builder, location, i64, bits,
                                             true),
          arith::ShLIOp::create(builder, location, child, constant(6)));
    }
    // `child` names a leaf word: run it unless its Active owners are idle.
    // Branch on whether leaf word `word` holds a pending Active owner. Only
    // the word shared with the first deferred owners needs a mask, so test
    // it on the nonempty path alone.
    auto branchOnActive = [&](Value word, Block *active,
                              ValueRange activeOperands, Block *idle,
                              ValueRange idleOperands) {
      Value leaf =
          LLVM::LoadOp::create(builder, location, i64, ingressWord(word, 0), 8);
      auto nonzero = [&](Value value) -> Value {
        return arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::ne, value, constant(0));
      };
      if (!hasDeferred || activeBits % 64 == 0) {
        cf::CondBranchOp::create(builder, location, nonzero(leaf), active,
                                 activeOperands, idle, idleOperands);
        return;
      }
      Block *nonempty = newBlock(), *shared = newBlock();
      cf::CondBranchOp::create(builder, location, nonzero(leaf), nonempty,
                               ValueRange{}, idle, idleOperands);
      builder.setInsertionPointToStart(nonempty);
      cf::CondBranchOp::create(
          builder, location,
          arith::CmpIOp::create(builder, location, arith::CmpIPredicate::eq,
                                word, constant(activeBits / 64)),
          shared, ValueRange{}, active, activeOperands);
      builder.setInsertionPointToStart(shared);
      cf::CondBranchOp::create(
          builder, location,
          nonzero(arith::AndIOp::create(
              builder, location, leaf,
              constant((uint64_t{1} << (activeBits % 64)) - 1))),
          active, activeOperands, idle, idleOperands);
    };
    wordSwitch = newBlock(1);
    branchOnActive(child, wordSwitch, ValueRange{child}, clearFrom[1],
                   ValueRange{child});
    // After a word: poll termination once (ranked groups do not poll; an
    // oscillating group returns here every visit), then keep the word's
    // dirty bit only while Active work remains.
    afterWord = newBlock(1);
    afterWord->addArgument(i32, location);
    builder.setInsertionPointToStart(afterWord);
    Block *poll = newBlock(), *recheck = newBlock(), *stopping = newBlock();
    cf::CondBranchOp::create(
        builder, location,
        arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::eq,
            afterWord->getArgument(1),
            llvmConstant(builder, location, i32, TALOS_RT_OK)),
        poll, ValueRange{}, failed, ValueRange{afterWord->getArgument(1)});
    builder.setInsertionPointToStart(poll);
    Value termination = LLVM::LoadOp::create(
        builder, location, pointer,
        LLVM::AddressOfOp::create(builder, location, pointer,
                                  periodicTerminationName),
        8);
    cf::CondBranchOp::create(
        builder, location,
        LLVM::ICmpOp::create(builder, location, LLVM::ICmpPredicate::eq,
                             termination,
                             LLVM::ZeroOp::create(builder, location, pointer)),
        recheck, ValueRange{}, stopping, ValueRange{});
    builder.setInsertionPointToStart(stopping);
    cf::CondBranchOp::create(
        builder, location,
        arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::ne,
            LLVM::LoadOp::create(builder, location, i32, termination, 4),
            llvmConstant(builder, location, i32, 0)),
        stopped, ValueRange{}, recheck, ValueRange{});
    builder.setInsertionPointToStart(recheck);
    Value word = afterWord->getArgument(0);
    branchOnActive(word, dispatch, ValueRange{}, clearFrom[1],
                   ValueRange{word});
    builder.setInsertionPointToStart(activeEmpty);
    emitActiveEmpty();
  }
  SmallVector<APInt> cases;
  SmallVector<Block *> destinations;
  SmallVector<ValueRange> destinationOperands;
  // Every entry policy shares these groups and their local domain proofs.
  auto rankedExecutor = [&](unsigned index) -> StringRef {
    return index < plan.rankedGroupExecutors.size()
               ? StringRef(plan.rankedGroupExecutors[index])
               : StringRef{};
  };
  // Records whose subsumption mask contains each owner bit, computed once:
  // scanning every record per owner is quadratic in the owner count.
  SmallVector<SmallVector<unsigned, 1>> supersedingRecords(ownerCount);
  for (auto [parent, parentRecord] : llvm::enumerate(mergedFragments)) {
    const APInt &members = ownerSubsumptionMasks[parent];
    if (!allowedOwnerMask[parentRecord.bit] || members.isZero())
      continue;
    for (unsigned word = 0; word != members.getNumWords(); ++word)
      for (uint64_t bits = members.getRawData()[word]; bits; bits &= bits - 1)
        supersedingRecords[word * 64 + llvm::countr_zero(bits)].push_back(
            parent);
  }
  // Where one owner's execution continues: dispatch the next ready owner,
  // fail with its status, or stop the generated loop.
  struct OwnerTargets {
    Region *body;
    Value context;
    Value fourStateFallback;
    Block *dispatch;
    Block *failed;
    Block *stopped;
  };
  const OwnerTargets coordinatorTargets{&fastCoordinator.getBody(),
                                        fastEntry->getArgument(1),
                                        fourStateFallback,
                                        dispatch,
                                        failed,
                                        stopped};
  // Owner execution code is linear in the owners that share no ranked group.
  // A cyclic island can hold tens of thousands of them, and one coordinator
  // body of that size can neither be divided among backend partitions nor
  // pass through superlinear LLVM transforms. Beyond one segment, emit them
  // in bounded segment functions. A segment can continue with the global
  // minimum ready owner locally, and returns when selection needs the outer
  // coordinator or a runtime scheduling boundary.
  constexpr unsigned segmentShift = 9;
  unsigned directOwners = 0;
  for (auto [recordIndex, record] : llvm::enumerate(mergedFragments))
    directOwners += !swept(record.bit) && !executors[recordIndex].empty() &&
                    allowedOwnerMask[record.bit] &&
                    rankedExecutor(recordIndex).empty();
  const bool segmented = directOwners > (1u << segmentShift);
  struct Segment {
    LLVM::LLVMFuncOp function;
    OwnerTargets targets;
    SmallVector<APInt> cases;
    SmallVector<Block *> destinations;
  };
  std::map<uint64_t, Segment> segments;
  auto segmentFor = [&](uint64_t index) -> Segment & {
    auto [found, inserted] = segments.try_emplace(index);
    Segment &segment = found->second;
    if (!inserted)
      return segment;
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToEnd(module.getBody());
    segment.function = LLVM::LLVMFuncOp::create(
        builder, location,
        (Twine(functionName) + ".segment_" + Twine(index)).str(),
        LLVM::LLVMFunctionType::get(i32, {pointer, i64, pointer}, false));
    Block *entry = segment.function.addEntryBlock(builder);
    Block *resume = new Block, *segmentFailed = new Block,
          *segmentStopped = new Block;
    segmentFailed->addArgument(i32, location);
    segment.function.getBody().push_back(resume);
    segment.function.getBody().push_back(segmentFailed);
    segment.function.getBody().push_back(segmentStopped);
    builder.setInsertionPointToStart(segmentFailed);
    LLVM::ReturnOp::create(builder, location, segmentFailed->getArgument(0));
    builder.setInsertionPointToStart(segmentStopped);
    LLVM::ReturnOp::create(
        builder, location,
        llvmConstant(builder, location, i32, TALOS_RT_TIER_UNAVAILABLE));
    segment.targets = {&segment.function.getBody(),
                       entry->getArgument(0),
                       entry->getArgument(2),
                       resume,
                       segmentFailed,
                       segmentStopped};
    return segment;
  };
  // One owner's activation protocol, entered at the builder's insertion
  // point with its pending bit set; it continues at targets.dispatch.
  auto emitOwnerExecution = [&](unsigned recordIndex,
                                const talos_rt_native_merged_fragment &record,
                                const OwnerTargets &targets) {
    if (readyLayout.hasSummaries()) {
      APInt superseding;
      if (!supersedingRecords[record.bit].empty()) {
        superseding = APInt(ownerCount, 0);
        for (unsigned parent : supersedingRecords[record.bit])
          superseding.setBit(mergedFragments[parent].bit);
      }
      if (plan.writableVPI) {
        Value parents = llvmConstant(builder, location, i64, 0);
        for (unsigned parent : supersedingRecords[record.bit]) {
          Value pending = maskedOwnerWords(
              builder, location, ingressAddress(),
              APInt::getOneBitSet(ownerCount, mergedFragments[parent].bit));
          pending = arith::SelectOp::create(
              builder, location, ownerWritableClean(parent, targets.context),
              pending, llvmConstant(builder, location, i64, 0));
          parents = arith::OrIOp::create(builder, location, parents, pending);
        }
        // The ordinary normalization below must not drop exact work when its
        // containing Tier-1 owner has lost only its scheduling/override proof.
        superseding.clearAllBits();
        Value covered = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::ne, parents,
            llvmConstant(builder, location, i64, 0));
        Block *skip = new Block, *uncovered = new Block;
        targets.body->push_back(skip);
        targets.body->push_back(uncovered);
        cf::CondBranchOp::create(builder, location, covered, skip, ValueRange{},
                                 uncovered, ValueRange{});
        builder.setInsertionPointToStart(skip);
        clearIngressMask(APInt::getOneBitSet(ownerCount, record.bit));
        cf::BranchOp::create(builder, location, targets.dispatch);
        builder.setInsertionPointToStart(uncovered);
      }
      if (!superseding.isZero()) {
        // Normalize only the selected exact owner. Eagerly walking every
        // subsumption relation at every dispatch is quadratic in a large
        // clock group. Do not jump straight to its parent: unrelated lower
        // ready owners must retain their deterministic priority.
        Value parents =
            maskedOwnerWords(builder, location, ingressAddress(), superseding);
        Value covered = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::ne, parents,
            llvmConstant(builder, location, i64, 0));
        Block *skip = new Block;
        Block *uncovered = new Block;
        targets.body->push_back(skip);
        targets.body->push_back(uncovered);
        cf::CondBranchOp::create(builder, location, covered, skip, ValueRange{},
                                 uncovered, ValueRange{});
        builder.setInsertionPointToStart(skip);
        clearIngressMask(APInt::getOneBitSet(ownerCount, record.bit));
        cf::BranchOp::create(builder, location, targets.dispatch);
        builder.setInsertionPointToStart(uncovered);
      }
    }
    if (plan.writableVPI) {
      Block *clean = new Block, *fine = new Block;
      targets.body->push_back(clean);
      targets.body->push_back(fine);
      cf::CondBranchOp::create(builder, location,
                               ownerWritableClean(recordIndex, targets.context),
                               clean, ValueRange{}, fine, ValueRange{});
      builder.setInsertionPointToStart(fine);
      // Consume only this activation. Exact existing ingress is retained;
      // clock-only full sweeps seed the original clock-triggered fine entries.
      // Do not replay upstream producers after an internal VPI deposit (38.34).
      clearIngressMask(APInt::getOneBitSet(ownerCount, record.bit));
      if (!ownerSubsumptionMasks[recordIndex].isZero()) {
        updateOwnerMask(builder, location, ingressAddress(),
                        plan.ownerFineIngress[recordIndex], /*clear=*/false, {},
                        &readyLayout);
        cf::BranchOp::create(builder, location, targets.dispatch);
      } else {
        LLVM::StoreOp::create(
            builder, location,
            llvmConstant(builder, location, builder.getI1Type(), 1),
            targets.fourStateFallback, 1);
        if (ownerMayTaintNBA(recordIndex))
          markOwnerNBATaint(recordIndex);
        Value status =
            LLVM::CallOp::create(
                builder, location, TypeRange{i32},
                "talos_rt_v1_scheduler_execute_aot_actor",
                ValueRange{targets.context, llvmConstant(builder, location, i32,
                                                         record.actor_slot)})
                .getResult();
        Value ok = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::eq, status,
            llvmConstant(builder, location, i32, TALOS_RT_OK));
        cf::CondBranchOp::create(builder, location, ok, targets.dispatch,
                                 ValueRange{}, targets.failed,
                                 ValueRange{status});
      }
      builder.setInsertionPointToStart(clean);
    }
    Value ownerBit =
        llvmConstant(builder, location, i64, uint64_t{1} << (record.bit % 64));
    Value selectedPromotionPending;
    {
      Value pending = LLVM::AddressOfOp::create(builder, location, pointer,
                                                promotionPendingMaskName);
      selectedPromotionPending = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::ne,
          arith::AndIOp::create(
              builder, location, ownerBit,
              loadOwnerWord(builder, location, pending, record.bit / 64)),
          llvmConstant(builder, location, i64, 0));
    }
    if (mergedTwoStateExecutors[recordIndex].empty()) {
      LLVM::StoreOp::create(
          builder, location,
          llvmConstant(builder, location, builder.getI1Type(), 1),
          targets.fourStateFallback, 1);
      if (ownerMayTaintNBA(recordIndex))
        markOwnerNBATaint(recordIndex);
    }
    auto executor =
        executorSymbols.lookup<LLVM::LLVMFuncOp>(executors[recordIndex]);
    auto twoStateExecutor = executorSymbols.lookup<LLVM::LLVMFuncOp>(
        mergedTwoStateExecutors[recordIndex]);
    bool convergenceOwner =
        (executor &&
         ::talos::schedule::has<schedule::metadata::evalTier2Convergence>(
             executor)) ||
        (twoStateExecutor &&
         ::talos::schedule::has<schedule::metadata::evalTier2Convergence>(
             twoStateExecutor));
    // A convergence owner consumes its old dirty bit before executing. Any
    // transition published by the activation then remains queued and drives
    // another local fixpoint iteration. Non-convergence owners retain the
    // clock-kernel rule below, which suppresses their implicit self fanout.
    const APInt &subsumedOwnerMask = ownerSubsumptionMasks[recordIndex];
    APInt consumed = subsumedOwnerMask;
    consumed.setBit(record.bit);
    if (convergenceOwner)
      clearIngressMask(consumed);
    Value executeStatus;
    if (!mergedTwoStateExecutors[recordIndex].empty()) {
      Block *checkPromotion = new Block;
      Block *executeFourState = new Block;
      Block *executeTwoState = new Block;
      Block *executeJoin = new Block;
      executeJoin->addArgument(i32, location);
      targets.body->push_back(checkPromotion);
      targets.body->push_back(executeFourState);
      targets.body->push_back(executeTwoState);
      targets.body->push_back(executeJoin);
      cf::CondBranchOp::create(builder, location, selectedPromotionPending,
                               checkPromotion, ValueRange{}, executeTwoState,
                               ValueRange{});
      builder.setInsertionPointToStart(checkPromotion);
      Value kernelReady =
          emitOwnerKernelReady(builder, location, recordIndex,
                               clockedKernelOwners.contains(recordIndex), executorSymbols);
      cf::CondBranchOp::create(builder, location, kernelReady, executeTwoState,
                               ValueRange{}, executeFourState, ValueRange{});
      builder.setInsertionPointToStart(executeFourState);
      LLVM::StoreOp::create(
          builder, location,
          llvmConstant(builder, location, builder.getI1Type(), 1),
          targets.fourStateFallback, 1);
      if (ownerMayTaintNBA(recordIndex))
        markOwnerNBATaint(recordIndex);
      Value fourStateStatus =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              SymbolRefAttr::get(context, executors[recordIndex]),
              ValueRange{targets.context})
              .getResult();
      cf::BranchOp::create(builder, location, executeJoin,
                           ValueRange{fourStateStatus});
      builder.setInsertionPointToStart(executeTwoState);
      Value twoStateStatus =
          LLVM::CallOp::create(
              builder, location, TypeRange{i32},
              SymbolRefAttr::get(context, mergedTwoStateExecutors[recordIndex]),
              ValueRange{targets.context})
              .getResult();
      ::talos::schedule::set<::talos::schedule::Field::EvalProvenTwoStateCall>(
          twoStateStatus.getDefiningOp(), builder.getUnitAttr());
      cf::BranchOp::create(builder, location, executeJoin,
                           ValueRange{twoStateStatus});
      builder.setInsertionPointToStart(executeJoin);
      executeStatus = executeJoin->getArgument(0);
    } else {
      executeStatus = LLVM::CallOp::create(
                          builder, location, TypeRange{i32},
                          SymbolRefAttr::get(context, executors[recordIndex]),
                          ValueRange{targets.context})
                          .getResult();
    }
    if (!convergenceOwner)
      clearIngressMask(consumed);
    else if (subsumedOwnerMask != 0) {
      Value queuedMembers = maskedOwnerWords(
          builder, location, ingressAddress(), subsumedOwnerMask);
      Value membersPending = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::ne, queuedMembers,
          llvmConstant(builder, location, i64, 0));
      clearIngressMask(subsumedOwnerMask);
      updateOwnerMask(builder, location, ingressAddress(),
                      APInt::getOneBitSet(ownerCount, record.bit),
                      /*clear=*/false, membersPending, &readyLayout);
    }
    Value executeOK = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, executeStatus,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    bool mayTerminate =
        (executor &&
         ::talos::schedule::has<schedule::metadata::evalMayTerminate>(
             executor)) ||
        (twoStateExecutor &&
         ::talos::schedule::has<schedule::metadata::evalMayTerminate>(
             twoStateExecutor));
    // A convergence owner may republish itself indefinitely. Poll the
    // branch-only termination word after each member activation, before the
    // coordinator follows the dirty-mask backedge. Waiting for the commit
    // boundary cannot interrupt a genuinely oscillating SCC because that
    // boundary is reachable only after its ready bit becomes clear.
    mayTerminate |= convergenceOwner;
    bool infallible =
        executor &&
        ::talos::schedule::has<schedule::metadata::evalInfallible>(executor) &&
        (!twoStateExecutor ||
         ::talos::schedule::has<schedule::metadata::evalInfallible>(
             twoStateExecutor));
    if (infallible && !mayTerminate) {
      cf::BranchOp::create(builder, location, targets.dispatch);
      return;
    }
    if (!mayTerminate) {
      cf::CondBranchOp::create(builder, location, executeOK, targets.dispatch,
                               ValueRange{}, targets.failed,
                               ValueRange{executeStatus});
      return;
    }
    Block *checkTermination = new Block;
    Block *loadTermination = new Block;
    targets.body->push_back(checkTermination);
    if (loadTermination)
      targets.body->push_back(loadTermination);
    cf::CondBranchOp::create(builder, location, executeOK, checkTermination,
                             ValueRange{}, targets.failed,
                             ValueRange{executeStatus});
    builder.setInsertionPointToStart(checkTermination);
    Value terminationAddress =
        LLVM::LoadOp::create(builder, location, pointer,
                             LLVM::AddressOfOp::create(builder, location,
                                                       pointer,
                                                       periodicTerminationName),
                             8)
            .getResult();
    Value noTerminationAddress = LLVM::ICmpOp::create(
        builder, location, LLVM::ICmpPredicate::eq, terminationAddress,
        LLVM::ZeroOp::create(builder, location, pointer));
    cf::CondBranchOp::create(builder, location, noTerminationAddress,
                             targets.dispatch, ValueRange{}, loadTermination,
                             ValueRange{});
    builder.setInsertionPointToStart(loadTermination);
    Value termination =
        LLVM::LoadOp::create(builder, location, i32, terminationAddress, 4);
    Value stopping = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne, termination,
        llvmConstant(builder, location, i32, 0));
    cf::CondBranchOp::create(builder, location, stopping, targets.stopped,
                             ValueRange{}, targets.dispatch, ValueRange{});
  };
  // Call a ranked group at the builder's insertion point, then continue at
  // targets.dispatch; `poll` is an empty block of targets.body.
  auto emitRankedCall = [&](StringRef ranked, const OwnerTargets &targets,
                            Block *poll) {
    LLVM::CallOp::create(builder, location, TypeRange{},
                         SymbolRefAttr::get(context, ranked),
                         ValueRange{targets.context});
    // Finite sweeps return here even for a true oscillator. Consume no
    // owner after the call: backward publications belong to the next
    // activation. Termination is polled at this real group boundary.
    Value address = LLVM::LoadOp::create(
        builder, location, pointer,
        LLVM::AddressOfOp::create(builder, location, pointer,
                                  periodicTerminationName),
        8);
    Value absent = LLVM::ICmpOp::create(
        builder, location, LLVM::ICmpPredicate::eq, address,
        LLVM::ZeroOp::create(builder, location, pointer));
    cf::CondBranchOp::create(builder, location, absent, targets.dispatch,
                             ValueRange{}, poll, ValueRange{});
    builder.setInsertionPointToStart(poll);
    Value stopping = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne,
        LLVM::LoadOp::create(builder, location, i32, address, 4),
        llvmConstant(builder, location, i32, 0));
    cf::CondBranchOp::create(builder, location, stopping, targets.stopped,
                             ValueRange{}, targets.dispatch, ValueRange{});
  };
  llvm::StringMap<Block *> rankedEntries;
  for (auto [recordIndex, record] : llvm::enumerate(mergedFragments)) {
    if (swept(record.bit) || executors[recordIndex].empty())
      continue;
    if (!allowedOwnerMask[record.bit])
      continue;
    StringRef ranked = rankedExecutor(recordIndex);
    if (!ranked.empty()) {
      auto [entry, inserted] = rankedEntries.try_emplace(ranked, nullptr);
      if (inserted) {
        Block *execute = new Block, *poll = new Block;
        fastCoordinator.getBody().push_back(execute);
        fastCoordinator.getBody().push_back(poll);
        entry->second = execute;
        builder.setInsertionPointToStart(execute);
        emitRankedCall(ranked, coordinatorTargets, poll);
      }
      cases.push_back(APInt(64, record.bit));
      destinations.push_back(entry->second);
      destinationOperands.push_back(ValueRange{});
      continue;
    }
    // Owners above one segment execute in their segment function.
    Segment *segment =
        segmented ? &segmentFor(record.bit >> segmentShift) : nullptr;
    const OwnerTargets &targets =
        segment ? segment->targets : coordinatorTargets;
    Block *execute = new Block;
    targets.body->push_back(execute);
    if (segment) {
      segment->cases.push_back(APInt(64, record.bit));
      segment->destinations.push_back(execute);
    } else {
      cases.push_back(APInt(64, record.bit));
      destinations.push_back(execute);
      destinationOperands.push_back(ValueRange{});
    }
    builder.setInsertionPointToStart(execute);
    emitOwnerExecution(recordIndex, record, targets);
  }
  Block *otherOwner = stopped;
  if (segmented) {
    // A segmented owner bit selects its segment; the segment's own switch
    // stops on a bit that names no owner, exactly as the coordinator does.
    otherOwner = new Block;
    fastCoordinator.getBody().push_back(otherOwner);
    SmallVector<APInt> segmentCases;
    SmallVector<Block *> segmentCalls;
    for (auto &[index, segment] : segments) {
      // A segment runs one owner and returns: the coordinator selects the
      // next one (Active owners of a multi-word set are swept by word).
      builder.setInsertionPointToStart(segment.targets.dispatch);
      LLVM::ReturnOp::create(builder, location,
                             llvmConstant(builder, location, i32, TALOS_RT_OK));
      builder.setInsertionPointToEnd(&segment.function.getBody().front());
      LLVM::SwitchOp::create(
          builder, location, segment.function.getArgument(1),
          segment.targets.stopped, ValueRange{}, segment.cases,
          segment.destinations,
          SmallVector<ValueRange>(segment.cases.size(), ValueRange{}),
          ArrayRef<int32_t>{});
      // Infallible owners never branch to the failure exit. Do not leave an
      // unreachable block for later lowering to skip.
      for (Block *exit : {segment.targets.dispatch, segment.targets.failed})
        if (exit->hasNoPredecessors())
          exit->erase();
      Block *call = new Block;
      fastCoordinator.getBody().push_back(call);
      builder.setInsertionPointToStart(call);
      Value status = LLVM::CallOp::create(builder, location, segment.function,
                                          ValueRange{fastEntry->getArgument(1),
                                                     bit, fourStateFallback})
                         .getResult();
      Value ok = arith::CmpIOp::create(
          builder, location, arith::CmpIPredicate::eq, status,
          llvmConstant(builder, location, i32, TALOS_RT_OK));
      cf::CondBranchOp::create(builder, location, ok, dispatch, ValueRange{},
                               failed, ValueRange{status});
      segmentCases.push_back(APInt(64, index));
      segmentCalls.push_back(call);
    }
    builder.setInsertionPointToStart(otherOwner);
    Value segmentIndex = arith::ShRUIOp::create(
        builder, location, bit,
        llvmConstant(builder, location, i64, segmentShift));
    LLVM::SwitchOp::create(
        builder, location, segmentIndex, stopped, ValueRange{}, segmentCases,
        segmentCalls,
        SmallVector<ValueRange>(segmentCases.size(), ValueRange{}),
        ArrayRef<int32_t>{});
  }
  builder.setInsertionPointToEnd(switchBlock);
  LLVM::SwitchOp::create(builder, location, bit, otherOwner, ValueRange{},
                         cases, destinations, destinationOperands,
                         ArrayRef<int32_t>{});
  // Without deferred owners a sweep leaves the switch unreachable. With them,
  // a runtime calendar's commit path branches here only once it is emitted.
  if (!hasDeferred && switchBlock->hasNoPredecessors())
    switchBlock->erase();

  // The word sweep's executors: one function per leaf word that holds Active
  // owners. It tests and runs them in rank order (lowest bit first; a ranked
  // group runs at its first member in the word and executes all of its
  // pending members), so it performs exactly the evaluations the per-owner
  // selection would (IEEE 1800-2023 4.5). A publication to an earlier word
  // sets that word's dirty bit, and the coordinator runs it next; within a
  // word the backward owner runs at the next visit. Both are Active-region
  // orders (4.7).
  if (wordSwitch) {
    DenseMap<uint32_t, unsigned> bitRecords;
    for (auto [recordIndex, record] : llvm::enumerate(mergedFragments))
      bitRecords.try_emplace(record.bit, recordIndex);
    SmallVector<APInt> wordCases;
    SmallVector<Block *> wordCalls;
    for (uint64_t word = 0; word * 64 < activeBits; ++word) {
      struct Item {
        StringRef ranked;
        uint64_t mask;
        std::optional<unsigned> record;
      };
      SmallVector<Item> items;
      llvm::StringMap<size_t> rankedItems;
      for (uint64_t owner = word * 64,
                    end = std::min<uint64_t>(activeBits, word * 64 + 64);
           owner != end; ++owner) {
        uint64_t mask = uint64_t{1} << (owner % 64);
        auto found = bitRecords.find(owner);
        // A pending owner without an executor stops the generated loop, as
        // the per-owner switch does.
        if (found == bitRecords.end() || executors[found->second].empty() ||
            !allowedOwnerMask[owner]) {
          items.push_back({StringRef{}, mask, std::nullopt});
          continue;
        }
        StringRef ranked = rankedExecutor(found->second);
        if (ranked.empty()) {
          items.push_back({StringRef{}, mask, found->second});
          continue;
        }
        auto [item, inserted] = rankedItems.try_emplace(ranked, items.size());
        if (inserted)
          items.push_back({ranked, mask, std::nullopt});
        else
          items[item->second].mask |= mask;
      }
      // The gate tests the whole last word when no owner is deferred. A bit
      // past the last owner names none and stops, as the switch's default.
      if (!hasDeferred && activeBits % 64 != 0 && activeBits / 64 == word)
        items.push_back({StringRef{}, ~((uint64_t{1} << (activeBits % 64)) - 1),
                         std::nullopt});
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToEnd(module.getBody());
      auto function = LLVM::LLVMFuncOp::create(
          builder, location,
          (Twine(functionName) + ".word_" + Twine(word)).str(),
          LLVM::LLVMFunctionType::get(i32, {pointer, pointer}, false));
      Block *entry = function.addEntryBlock(builder);
      Block *wordFailed = new Block, *wordStopped = new Block;
      wordFailed->addArgument(i32, location);
      function.getBody().push_back(wordFailed);
      function.getBody().push_back(wordStopped);
      builder.setInsertionPointToStart(wordFailed);
      LLVM::ReturnOp::create(builder, location, wordFailed->getArgument(0));
      builder.setInsertionPointToStart(wordStopped);
      LLVM::ReturnOp::create(
          builder, location,
          llvmConstant(builder, location, i32, TALOS_RT_TIER_UNAVAILABLE));
      Value wordContext = entry->getArgument(0);
      Block *current = entry;
      for (auto [index, item] : llvm::enumerate(items)) {
        builder.setInsertionPointToEnd(current);
        Block *execute = new Block, *next = new Block;
        function.getBody().push_back(execute);
        function.getBody().push_back(next);
        Value pending = arith::AndIOp::create(
            builder, location,
            loadOwnerWord(builder, location, ingressAddress(), word),
            llvmConstant(builder, location, i64, item.mask));
        cf::CondBranchOp::create(
            builder, location,
            arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                  pending,
                                  llvmConstant(builder, location, i64, 0)),
            execute, ValueRange{}, next, ValueRange{});
        // After an owner runs, keep the coordinator's per-selection checks
        // before the next one: a priority signal hands off (as at dispatch)
        // and an ordered NBA queue failure ends the call. The coordinator
        // checks again after the last owner.
        Block *continuation = next;
        if (index + 1 != items.size() &&
            (!item.ranked.empty() || item.record) &&
            (prioritySignalHandoff || plan.hasOrderedNBA)) {
          continuation = new Block;
          function.getBody().push_back(continuation);
          builder.setInsertionPointToStart(continuation);
          // The coordinator's order: a queue failure before a handoff.
          if (plan.hasOrderedNBA) {
            Value status = LLVM::LoadOp::create(
                builder, location, i32, evalNBAQueueField(builder, location, 3),
                4);
            Block *proceed = next;
            if (prioritySignalHandoff) {
              proceed = new Block;
              function.getBody().push_back(proceed);
            }
            cf::CondBranchOp::create(
                builder, location,
                arith::CmpIOp::create(
                    builder, location, arith::CmpIPredicate::eq, status,
                    llvmConstant(builder, location, i32, TALOS_RT_OK)),
                proceed, ValueRange{}, wordFailed, ValueRange{status});
            if (prioritySignalHandoff)
              builder.setInsertionPointToStart(proceed);
          }
          if (prioritySignalHandoff) {
            Value signal =
                LLVM::CallOp::create(
                    builder, location, TypeRange{i32},
                    SymbolRefAttr::get(
                        context,
                        "talos_rt_v1_scheduler_priority_signal_pending"),
                    ValueRange{wordContext})
                    .getResult();
            cf::CondBranchOp::create(
                builder, location,
                arith::CmpIOp::create(builder, location,
                                      arith::CmpIPredicate::ne, signal,
                                      llvmConstant(builder, location, i32, 0)),
                wordFailed,
                ValueRange{llvmConstant(builder, location, i32,
                                        TALOS_RT_AOT_CHECKPOINT)},
                next, ValueRange{});
          }
        }
        builder.setInsertionPointToStart(execute);
        const OwnerTargets targets{
            &function.getBody(), wordContext, entry->getArgument(1),
            continuation,        wordFailed,  wordStopped};
        if (!item.ranked.empty()) {
          // The coordinator polls termination after the word (see afterWord).
          LLVM::CallOp::create(builder, location, TypeRange{},
                               SymbolRefAttr::get(context, item.ranked),
                               ValueRange{wordContext});
          cf::BranchOp::create(builder, location, continuation);
        } else if (item.record) {
          emitOwnerExecution(*item.record, mergedFragments[*item.record],
                             targets);
        } else {
          cf::BranchOp::create(builder, location, wordStopped);
        }
        current = next;
      }
      builder.setInsertionPointToEnd(current);
      LLVM::ReturnOp::create(builder, location,
                             llvmConstant(builder, location, i32, TALOS_RT_OK));
      for (Block *exit : {wordFailed, wordStopped})
        if (exit->hasNoPredecessors())
          exit->erase();
      Block *call = new Block;
      fastCoordinator.getBody().push_back(call);
      builder.setInsertionPointToStart(call);
      Value status = LLVM::CallOp::create(builder, location, function,
                                          ValueRange{fastEntry->getArgument(1),
                                                     fourStateFallback})
                         .getResult();
      cf::BranchOp::create(builder, location, afterWord,
                           ValueRange{wordSwitch->getArgument(0), status});
      wordCases.push_back(APInt(64, word));
      wordCalls.push_back(call);
    }
    builder.setInsertionPointToStart(wordSwitch);
    LLVM::SwitchOp::create(
        builder, location, wordSwitch->getArgument(0), stopped, ValueRange{},
        wordCases, wordCalls,
        SmallVector<ValueRange>(wordCases.size(), ValueRange{}),
        ArrayRef<int32_t>{});
  }

  // Wakes of NBA updates performed early (see evalNBAHeldWakesName) join the
  // ingress set once the updates of their NBA region are complete (IEEE
  // 1800-2023 4.5, 4.6(b), 4.7): after the commit, or at quiescence when the
  // region staged nothing. Designs without held publications keep their
  // coordinator IR unchanged.
  bool holdsWakes = false;
  if (auto held = module.lookupSymbol<LLVM::GlobalOp>(evalNBAHeldWakesName))
    holdsWakes =
        ::talos::schedule::has<::talos::schedule::Field::EvalNbaHeldWords>(
            held);
  auto emitHeldMerge = [&](Block *merged, ValueRange mergedOperands,
                           Block *none, ValueRange noneOperands) {
    emitNBAHeldWakeMerge(builder, location, module, merged, mergedOperands,
                         none, noneOperands);
  };
  // Every return hands the held wakes back as ordinary ingress first (see
  // releaseNBAHeldWakesBeforeReturns): a return before the region's updates
  // are complete (a runtime cut, a priority-signal checkpoint, a stop or a
  // failure) then runs them as Active events, as without holding, which the
  // direct-store proofs already admit.
  auto emitReturns = [&] {
    builder.setInsertionPointToStart(complete);
    LLVM::ReturnOp::create(builder, location, complete->getArgument(0));
    builder.setInsertionPointToStart(stopped);
    LLVM::ReturnOp::create(
        builder, location,
        llvmConstant(builder, location, i32, TALOS_RT_TIER_UNAVAILABLE));
    builder.setInsertionPointToStart(failed);
    LLVM::ReturnOp::create(builder, location, failed->getArgument(0));
    releaseNBAHeldWakesBeforeReturns(fastCoordinator);
  };

  builder.setInsertionPointToStart(commit);
  if (::talos::schedule::has<::talos::schedule::Field::EvalRuntimeCalendar>(
          module)) {
    // Keep the eval continuation active across NBA. The common loop drains
    // runtime Active/Inactive work at the cut, then completes the remaining
    // NBA queues before any generated or runtime Active reader can resume.
    // IEEE 1800-2023 4.4.2.3-4.4.2.4 requires Inactive to settle before NBA;
    // 4.5 permits new Active evaluation only after the whole NBA event batch.
    // The captured prefix retains 4.6(b) assignment order and 4.9.4/10.4.2
    // enqueue-time RHS/target values; runtime cuts never reevaluate them.
    getOrDeclareLLVMFunction(module, "talos_rt_v1_scheduler_prepare_eval_nba",
                             i32, {pointer, pointer});
    getOrDeclareLLVMFunction(module, "talos_rt_v1_scheduler_complete_eval_nba",
                             i32, {pointer, i32, i32});
    Value region = entryAlloca(builder, location, i32, 1, 4);
    Value prepareStatus =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             "talos_rt_v1_scheduler_prepare_eval_nba",
                             ValueRange{fastEntry->getArgument(1), region})
            .getResult();
    Block *prepared = new Block, *commitPrefix = new Block;
    fastCoordinator.getBody().push_back(prepared);
    fastCoordinator.getBody().push_back(commitPrefix);
    Value prepareOK = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, prepareStatus,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    cf::CondBranchOp::create(builder, location, prepareOK, prepared,
                             ValueRange{}, failed, ValueRange{prepareStatus});
    builder.setInsertionPointToStart(prepared);
    // The cut ran a $finish and the final procedures (IEEE 1800-2023 9.2.3):
    // dispatch no further owner and commit nothing of this slot.
    Value terminatedAtCut = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq,
        LLVM::LoadOp::create(builder, location, i32, region, 4),
        llvmConstant(builder, location, i32, TALOS_RT_EVAL_NBA_TERMINATED));
    Block *running = new Block;
    fastCoordinator.getBody().push_back(running);
    cf::CondBranchOp::create(
        builder, location, terminatedAtCut, complete,
        ValueRange{llvmConstant(builder, location, i32, TALOS_RT_OK)}, running,
        ValueRange{});
    builder.setInsertionPointToStart(running);
    Value ingress = sweep
                        ? activeDirty()
                        : maskedOwnerWords(builder, location, ingressAddress(),
                                           allOwners & ~deferredOwnerMask);
    Value hasIngress = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne, ingress,
        llvmConstant(builder, location, ingress.getType(), 0));
    Block *quiescent = performCommit;
    if (hasDeferred) {
      // Every Active and Inactive event of this pass has run. Execute the
      // lowest pending deferred owner, then settle what it wakes before the
      // cut is taken again.
      quiescent = new Block;
      fastCoordinator.getBody().push_back(quiescent);
    }
    cf::CondBranchOp::create(builder, location, hasIngress, dispatch,
                             ValueRange{}, quiescent, ValueRange{});
    if (hasDeferred) {
      // The cut just above reported any finish, and nothing has run since.
      builder.setInsertionPointToStart(quiescent);
      for (unsigned word = plan.firstDeferredBit / 64;
           word * 64 < mergedFragments.size(); ++word) {
        Value pending = arith::AndIOp::create(
            builder, location,
            loadOwnerWord(builder, location, ingressAddress(), word),
            llvmConstant(builder, location, i64,
                         ownerMaskWord(deferredOwnerMask, word)));
        Value found = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::ne, pending,
            llvmConstant(builder, location, i64, 0));
        Block *execute = new Block, *next = new Block;
        fastCoordinator.getBody().push_back(execute);
        fastCoordinator.getBody().push_back(next);
        cf::CondBranchOp::create(builder, location, found, execute,
                                 ValueRange{}, next, ValueRange{});
        builder.setInsertionPointToStart(execute);
        Value owner = arith::AddIOp::create(
            builder, location,
            LLVM::CountTrailingZerosOp::create(builder, location, i64, pending,
                                               true),
            llvmConstant(builder, location, i64, uint64_t{word} * 64));
        cf::BranchOp::create(builder, location, switchBlock, ValueRange{owner});
        builder.setInsertionPointToStart(next);
      }
      cf::BranchOp::create(builder, location, performCommit);
    }
    builder.setInsertionPointToStart(performCommit);
    Value barrier = LLVM::LoadOp::create(builder, location, i32, region, 4);
    Value isNBA = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, barrier,
        llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA));
    if (!holdsWakes) {
      cf::CondBranchOp::create(
          builder, location, isNBA, commitPrefix, ValueRange{}, complete,
          ValueRange{llvmConstant(builder, location, i32, TALOS_RT_OK)});
    } else {
      Block *noCommit = new Block;
      fastCoordinator.getBody().push_back(noCommit);
      cf::CondBranchOp::create(builder, location, isNBA, commitPrefix,
                               ValueRange{}, noCommit, ValueRange{});
      // No NBA barrier: the generated region staged nothing, so its early
      // updates are complete and their wakes run now.
      builder.setInsertionPointToStart(noCommit);
      emitHeldMerge(dispatch, ValueRange{}, complete,
                    llvmConstant(builder, location, i32, TALOS_RT_OK));
    }
    builder.setInsertionPointToStart(commitPrefix);
    LLVM::StoreOp::create(builder, location,
                          llvmConstant(builder, location, i32, 0), changed, 4);
    Value prefixStatus =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             "__talos_aot_runtime_nba_commit_v1",
                             ValueRange{fastEntry->getArgument(0),
                                        fastEntry->getArgument(1), barrier,
                                        changed})
            .getResult();
    Value prefixOK = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, prefixStatus,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    cf::CondBranchOp::create(builder, location, prefixOK, afterCommit,
                             ValueRange{}, failed, ValueRange{prefixStatus});
    builder.setInsertionPointToStart(afterCommit);
    Value status =
        LLVM::CallOp::create(builder, location, TypeRange{i32},
                             "talos_rt_v1_scheduler_complete_eval_nba",
                             ValueRange{fastEntry->getArgument(1), barrier,
                                        LLVM::LoadOp::create(builder, location,
                                                             i32, changed, 4)})
            .getResult();
    Value ok = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, status,
        llvmConstant(builder, location, i32, TALOS_RT_OK));
    if (!holdsWakes) {
      cf::CondBranchOp::create(builder, location, ok, dispatch, ValueRange{},
                               failed, ValueRange{status});
    } else {
      Block *committed = new Block;
      fastCoordinator.getBody().push_back(committed);
      cf::CondBranchOp::create(builder, location, ok, committed, ValueRange{},
                               failed, ValueRange{status});
      builder.setInsertionPointToStart(committed);
      emitHeldMerge(dispatch, ValueRange{}, dispatch, ValueRange{});
    }
    emitReturns();
    return success();
  }
  // NBA fanout often needs a blocking-only settle iteration. At quiescence,
  // skip the entire commit/probe path if that iteration staged no new NBA.
  // Dynamic slots do not set fixed-root dirty bits, so both representations
  // must be empty. This does not clear any four-state/promotion evidence.
  Value pendingNBA = llvmConstant(builder, location, i64, 0);
  if (nbaTaintWordCount != 0) {
    Value dirtyBase = LLVM::AddressOfOp::create(builder, location, pointer,
                                                nbaDirtyRootsName);
    for (uint32_t word = 0; word != nbaTaintWordCount; ++word) {
      Value dirty =
          LLVM::LoadOp::create(builder, location, i64,
                               byteGEP(builder, location, dirtyBase,
                                       uint64_t{word} * sizeof(uint64_t)),
                               8);
      pendingNBA = arith::OrIOp::create(builder, location, pendingNBA, dirty);
    }
  }
  // One summary word covers every fixed dynamic slot: this test runs at each
  // quiescent point, so its cost must not grow with the number of slots.
  if (plan.hasDynamicNBASlots) {
    Value pending = LLVM::LoadOp::create(
        builder, location, i32,
        LLVM::AddressOfOp::create(builder, location, pointer,
                                  evalDynamicNBAPendingName),
        4);
    pendingNBA = arith::OrIOp::create(
        builder, location, pendingNBA,
        arith::ExtUIOp::create(builder, location, i64, pending));
  }
  if (plan.hasOrderedNBA)
    pendingNBA = arith::OrIOp::create(
        builder, location, pendingNBA,
        arith::ExtUIOp::create(builder, location, i64,
                               evalNBAQueueSize(builder, location)));
  Value noNBA = arith::CmpIOp::create(builder, location,
                                      arith::CmpIPredicate::eq, pendingNBA,
                                      llvmConstant(builder, location, i64, 0));
  if (!holdsWakes) {
    cf::CondBranchOp::create(
        builder, location, noNBA, complete,
        ValueRange{llvmConstant(builder, location, i32, TALOS_RT_OK)},
        performCommit, ValueRange{});
  } else {
    // Nothing generated is staged: the generated part of the region was
    // performed early, and its wakes run now. Runtime-owned NBAs may still be
    // pending; running these wakes before them is the behavior without
    // holding, which the direct-store proofs admit. Otherwise the wakes wait
    // for the commit.
    Block *noStaged = new Block;
    fastCoordinator.getBody().push_back(noStaged);
    cf::CondBranchOp::create(builder, location, noNBA, noStaged, ValueRange{},
                             performCommit, ValueRange{});
    builder.setInsertionPointToStart(noStaged);
    emitHeldMerge(dispatch, ValueRange{}, complete,
                  llvmConstant(builder, location, i32, TALOS_RT_OK));
  }

  builder.setInsertionPointToStart(performCommit);
  {
    Block *commitBody = new Block;
    fastCoordinator.getBody().push_back(commitBody);
    emitRuntimeCut(TALOS_RT_REGION_OBSERVED, TALOS_RT_RUNTIME_YIELD_STAGED,
                   commitBody, ValueRange{});
    // The commit below continues in commitBody.
    builder.setInsertionPointToStart(commitBody);
  }
  {
    // A path dispatcher can reject after coordinator entry.  Observe that
    // rejection at the barrier so its four-state staging is never committed
    // by the compact value-plane-only path.
    Value dispatcherFallback = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne,
        LLVM::LoadOp::create(
            builder, location, builder.getI8Type(),
            LLVM::AddressOfOp::create(builder, location, pointer,
                                      evalStepFourStateFallbackName),
            1),
        llvmConstant(builder, location, builder.getI8Type(), 0));
    Value priorFallback = LLVM::LoadOp::create(
        builder, location, builder.getI1Type(), fourStateFallback, 1);
    LLVM::StoreOp::create(builder, location,
                          arith::OrIOp::create(builder, location, priorFallback,
                                               dispatcherFallback),
                          fourStateFallback, 1);
  }
  LLVM::StoreOp::create(builder, location,
                        llvmConstant(builder, location, i32, 0), changed, 4);
  Value commitStatus;
  {
    Block *fastTwoStateCommit = new Block;
    Block *canonicalTwoStateCommit = new Block;
    Block *fourStateCommit = new Block;
    Block *checkFallbackNBA = new Block;
    Block *checkCanonicalNBA = new Block;
    Block *selectFastNBA = new Block;
    Block *latchFastNBA = new Block;
    Block *commitJoin = new Block;
    commitJoin->addArgument(i32, location);
    fastCoordinator.getBody().push_back(checkFallbackNBA);
    fastCoordinator.getBody().push_back(checkCanonicalNBA);
    fastCoordinator.getBody().push_back(selectFastNBA);
    fastCoordinator.getBody().push_back(latchFastNBA);
    fastCoordinator.getBody().push_back(fastTwoStateCommit);
    fastCoordinator.getBody().push_back(canonicalTwoStateCommit);
    fastCoordinator.getBody().push_back(fourStateCommit);
    fastCoordinator.getBody().push_back(commitJoin);
    // Each NBA barrier calls the variant of its value domain; the variants
    // are declared here and defined from their source once it is complete.
    auto barrierVariant = [&](StringRef name, Type result) {
      getOrDeclareLLVMFunction(module, name, result,
                               {pointer, pointer, i32, pointer});
      return SymbolRefAttr::get(context, name);
    };
    auto tryStaticPublication = [&](StringRef variant) {
      auto attempt = LLVM::CallOp::create(
          builder, location, TypeRange{builder.getI1Type()},
          barrierVariant(variant, builder.getI1Type()),
          ValueRange{fastEntry->getArgument(0), fastEntry->getArgument(1),
                     llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA),
                     changed});
      auto *fallback = new Block;
      fastCoordinator.getBody().push_back(fallback);
      cf::CondBranchOp::create(
          builder, location, attempt.getResult(), commitJoin,
          ValueRange{llvmConstant(builder, location, i32, TALOS_RT_OK)},
          fallback, ValueRange{});
      builder.setInsertionPointToStart(fallback);
    };
    Value usedFallback = LLVM::LoadOp::create(
        builder, location, builder.getI1Type(), fourStateFallback, 1);
    cf::CondBranchOp::create(builder, location, usedFallback, checkFallbackNBA,
                             ValueRange{}, selectFastNBA, ValueRange{});
    auto markCurrentDirtyRootsFast = [&] {
      if (nbaTaintWordCount == 0)
        return;
      Value dirtyBase = LLVM::AddressOfOp::create(builder, location, pointer,
                                                  nbaDirtyRootsName);
      Value fastRootsBase = LLVM::AddressOfOp::create(
          builder, location, pointer, evalFastNBARootsName);
      for (uint32_t word = 0; word != nbaTaintWordCount; ++word) {
        Value dirty =
            LLVM::LoadOp::create(builder, location, i64,
                                 byteGEP(builder, location, dirtyBase,
                                         uint64_t{word} * sizeof(uint64_t)),
                                 8);
        Value fastAddress = byteGEP(builder, location, fastRootsBase,
                                    uint64_t{word} * sizeof(uint64_t));
        Value fastRoots =
            LLVM::LoadOp::create(builder, location, i64, fastAddress, 8);
        LLVM::StoreOp::create(
            builder, location,
            arith::OrIOp::create(builder, location, fastRoots, dirty),
            fastAddress, 8);
      }
    };
    builder.setInsertionPointToStart(selectFastNBA);
    Value fastRootsKnown =
        llvmConstant(builder, location, builder.getI1Type(), 0);
    if (nbaTaintWordCount != 0) {
      Value dirtyBase = LLVM::AddressOfOp::create(builder, location, pointer,
                                                  nbaDirtyRootsName);
      Value fastRootsBase = LLVM::AddressOfOp::create(
          builder, location, pointer, evalFastNBARootsName);
      Value missingFastRoot =
          llvmConstant(builder, location, builder.getI1Type(), 0);
      for (uint32_t word = 0; word != nbaTaintWordCount; ++word) {
        Value dirty =
            LLVM::LoadOp::create(builder, location, i64,
                                 byteGEP(builder, location, dirtyBase,
                                         uint64_t{word} * sizeof(uint64_t)),
                                 8);
        Value fastRoots =
            LLVM::LoadOp::create(builder, location, i64,
                                 byteGEP(builder, location, fastRootsBase,
                                         uint64_t{word} * sizeof(uint64_t)),
                                 8);
        Value missing = arith::AndIOp::create(
            builder, location, dirty,
            arith::XOrIOp::create(
                builder, location, fastRoots,
                llvmConstant(builder, location, i64, UINT64_MAX)));
        missingFastRoot = arith::OrIOp::create(
            builder, location, missingFastRoot,
            arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                  missing,
                                  llvmConstant(builder, location, i64, 0)));
      }
      fastRootsKnown = arith::OrIOp::create(
          builder, location, fastRootsKnown,
          arith::XOrIOp::create(
              builder, location, missingFastRoot,
              llvmConstant(builder, location, builder.getI1Type(), 1)));
    }
    // Known destination certificates persist across ordinary clocks. Keep
    // the value-only barrier on the hot path; X/Z recovery remains cold.
    markLikelyTrue(cf::CondBranchOp::create(
        builder, location, fastRootsKnown, fastTwoStateCommit, ValueRange{},
        checkCanonicalNBA, ValueRange{}));
    builder.setInsertionPointToStart(checkFallbackNBA);
    // A four-state owner may stage only known values. If its dirty roots have
    // zero canonical and staged unknown bits, rejoin the ordinary handoff:
    // canonicalize all dirty roots once if needed, latch the compact barrier
    // at that quiescent boundary, and keep it selected on later clocks. This
    // prevents an X-valued monitor closure from downgrading unrelated DUT
    // registers forever while retaining the four-state barrier for a
    // genuinely unknown write.
    Value fallbackNBAKnown =
        LLVM::CallOp::create(
            builder, location, TypeRange{builder.getI1Type()},
            SymbolRefAttr::get(context, nbaKnownName),
            ValueRange{
                llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA),
                llvmConstant(builder, location, builder.getI1Type(), 1),
                llvmConstant(builder, location, builder.getI1Type(), 1)})
            .getResult();
    cf::CondBranchOp::create(builder, location, fallbackNBAKnown, selectFastNBA,
                             ValueRange{}, fourStateCommit, ValueRange{});
    builder.setInsertionPointToStart(checkCanonicalNBA);
    Value canonicalNBAKnown =
        LLVM::CallOp::create(
            builder, location, TypeRange{builder.getI1Type()},
            SymbolRefAttr::get(context, nbaKnownName),
            ValueRange{
                llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA),
                llvmConstant(builder, location, builder.getI1Type(), 1),
                llvmConstant(builder, location, builder.getI1Type(), 0)})
            .getResult();
    markLikelyTrue(cf::CondBranchOp::create(
        builder, location, canonicalNBAKnown, latchFastNBA, ValueRange{},
        canonicalTwoStateCommit, ValueRange{}));
    builder.setInsertionPointToStart(latchFastNBA);
    markCurrentDirtyRootsFast();
    cf::BranchOp::create(builder, location, fastTwoStateCommit);
    builder.setInsertionPointToStart(fastTwoStateCommit);
    tryStaticPublication(staticNBAPublicationFastName);
    auto fastTwoStateCall = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        barrierVariant(staticNBACommitFastName, i32),
        ValueRange{fastEntry->getArgument(0), fastEntry->getArgument(1),
                   llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA),
                   changed});
    cf::BranchOp::create(builder, location, commitJoin,
                         ValueRange{fastTwoStateCall.getResult()});
    builder.setInsertionPointToStart(canonicalTwoStateCommit);
    // Clearing the current mask can leave X/Z elsewhere in a partial root.
    // Only the whole-root knownness query above may latch its certificate.
    tryStaticPublication(staticNBAPublicationTwoStateName);
    auto canonicalTwoStateCall = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        barrierVariant(staticNBACommitTwoStateName, i32),
        ValueRange{fastEntry->getArgument(0), fastEntry->getArgument(1),
                   llvmConstant(builder, location, i32, TALOS_RT_REGION_NBA),
                   changed});
    cf::BranchOp::create(builder, location, commitJoin,
                         ValueRange{canonicalTwoStateCall.getResult()});
    builder.setInsertionPointToStart(fourStateCommit);
    tryStaticPublication(staticNBAPublicationName);
    Value fourStateStatus =
        LLVM::CallOp::create(
            builder, location, TypeRange{i32},
            SymbolRefAttr::get(context, evalFourStateNBAHandoffName),
            ValueRange{fastEntry->getArgument(0), fastEntry->getArgument(1),
                       changed})
            .getResult();
    cf::BranchOp::create(builder, location, commitJoin,
                         ValueRange{fourStateStatus});
    builder.setInsertionPointToStart(commitJoin);
    commitStatus = commitJoin->getArgument(0);
  }
  Value commitOK = arith::CmpIOp::create(
      builder, location, arith::CmpIPredicate::eq, commitStatus,
      llvmConstant(builder, location, i32, TALOS_RT_OK));
  cf::CondBranchOp::create(builder, location, commitOK, afterCommit,
                           ValueRange{}, failed, ValueRange{commitStatus});

  builder.setInsertionPointToStart(afterCommit);
  if (holdsWakes) {
    Block *merged = new Block;
    fastCoordinator.getBody().push_back(merged);
    emitHeldMerge(merged, ValueRange{}, merged, ValueRange{});
    builder.setInsertionPointToStart(merged);
  }
  Value postNBAReady =
      sweep ? arith::OrIOp::create(builder, location, activeDirty(),
                                   maskedOwnerWords(builder, location,
                                                    ingressAddress(),
                                                    deferredOwnerMask))
            : combinedIngress();
  Value postNBAEmpty = arith::CmpIOp::create(
      builder, location, arith::CmpIPredicate::eq, postNBAReady,
      llvmConstant(builder, location, i64, 0));
  cf::CondBranchOp::create(builder, location, postNBAEmpty, complete,
                           ValueRange{commitStatus}, dispatch, ValueRange{});
  emitReturns();
  return success();
}

} // namespace talos::detail
