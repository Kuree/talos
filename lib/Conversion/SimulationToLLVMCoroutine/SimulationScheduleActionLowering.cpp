#include "SimulationEvalReadySet.h"
#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/DialectConversion.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <atomic>

using namespace mlir;

namespace talos {
namespace detail {
void declareSpecializedNBABatchRuntime(ModuleOp module);
void lowerSpecializedNBABatch(schedule::NativeNBABatchOp op,
                              bool declareRuntime);
void lowerNativeReadyRegion(schedule::NativeReadyRegionOp op,
                            const schedule::NativeGlobalLookup &globals);
} // namespace detail
namespace {
// Preserve the existing generated pending-set representation and publication
// boundary (IEEE 1800-2023 4.3, 4.5--4.7): no actor or observer executes inside
// this operation, and it does not coalesce source events. Preserve ascending
// read/add order even when source aliases the ready set. In particular, do not
// defer dirty-level writes past a later source read.
void materializeReadyMerge(schedule::NativeReadyMergeOp merge) {
  OpBuilder builder(merge);
  Location loc = merge.getLoc();
  detail::EvalReadySetLayout layout(merge.getCapacity());
  auto i64 = builder.getI64Type();
  auto constant = [&](uint64_t value) {
    return detail::llvmConstant(builder, loc, i64, value);
  };
  auto address = [&](Value base, Value word) -> Value {
    return LLVM::GEPOp::create(builder, loc, base.getType(), i64, base,
                               ValueRange{word});
  };
  auto load = [&](Value pointer) -> Value {
    return LLVM::LoadOp::create(builder, loc, i64, pointer, 8);
  };
  auto empty = [&](Value value) -> Value {
    return arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::eq, value,
                                 constant(0));
  };
  Block *entry = merge->getBlock();
  Block *done = entry->splitBlock(Block::iterator(merge));
  auto block = [&]() {
    auto *result = new Block;
    done->getParent()->getBlocks().insert(done->getIterator(), result);
    return result;
  };
  // A sparse source mostly holds empty words. When the unmasked words span at
  // least two groups, each group of `groupWords` words is tested at once, and
  // the words after the last whole group together; only a nonempty group is
  // merged word by word. A group is tested after every lower word is merged.
  // An empty one causes no write, and a nonempty one rereads each word just
  // before adding it, so the ascending read/add order above still holds when
  // source aliases the ready set. A group test is one short vector reduction
  // and a nonempty group rescans at most `groupWords` words; no cache size is
  // assumed. The last word's bits above capacity are masked once, after every
  // lower word.
  constexpr uint64_t groupWords = 8;
  uint64_t count = layout.counts[0];
  bool masked = layout.lastWordMask() != UINT64_MAX;
  uint64_t span = masked ? count - 1 : count;
  bool grouped = span >= 2 * groupWords;
  uint64_t wholeEnd = grouped ? span / groupWords * groupWords : 0;

  // Add one nonempty source word to its leaf and dirty bits.
  auto add = [&](Value index, Value selected) {
    Value leaf = address(merge.getBase(), index);
    LLVM::StoreOp::create(
        builder, loc, arith::OrIOp::create(builder, loc, load(leaf), selected),
        leaf, 8);
    // Every add ORs its dirty bits at each level, whatever the old leaf held:
    // only the coordinator's sweep clears a dirty bit, after it observes the
    // child empty (runtime::DirtyReadySetLayout).
    Value child = index;
    for (unsigned level = 1; level < layout.levels; ++level) {
      Value parent = arith::ShRUIOp::create(builder, loc, child, constant(6));
      Value slotIndex = arith::AddIOp::create(builder, loc, parent,
                                              constant(layout.offsets[level]));
      Value slot = address(merge.getBase(), slotIndex);
      Value bit = arith::ShLIOp::create(
          builder, loc, constant(1),
          arith::AndIOp::create(builder, loc, child, constant(63)));
      LLVM::StoreOp::create(builder, loc,
                            arith::OrIOp::create(builder, loc, load(slot), bit),
                            slot, 8);
      child = parent;
    }
  };
  // Whether the `width` words of source from `start` are all zero.
  auto emptyWords = [&](Value start, uint64_t width) -> Value {
    auto vector = VectorType::get({int64_t(width)}, i64);
    Value words = LLVM::LoadOp::create(builder, loc, vector,
                                       address(merge.getSource(), start), 8);
    return empty(LLVM::vector_reduce_or::create(builder, loc, i64, words));
  };

  // The last word, masked, after every lower word.
  Block *lastWordBlock = done;
  if (masked) {
    lastWordBlock = block();
    Block *addLast = block();
    builder.setInsertionPointToStart(lastWordBlock);
    Value index = constant(count - 1);
    Value selected = arith::AndIOp::create(
        builder, loc, load(address(merge.getSource(), index)),
        constant(layout.lastWordMask()));
    cf::CondBranchOp::create(builder, loc, empty(selected), done, addLast);
    builder.setInsertionPointToStart(addLast);
    add(index, selected);
    cf::BranchOp::create(builder, loc, done);
  }

  // A capacity within the first word leaves no unmasked word.
  builder.setInsertionPointToEnd(entry);
  if (!span) {
    cf::BranchOp::create(builder, loc, lastWordBlock);
    merge.erase();
    return;
  }

  // Groups [0, wholeEnd), with the next group's start as argument. Without
  // groups a word run continues with the last word.
  Block *nextGroup = nullptr;
  if (grouped) {
    nextGroup = block();
    nextGroup->addArgument(i64, loc);
  }

  // Words [word, end) one at a time.
  Block *head = block(), *update = block(), *advance = block();
  head->addArgument(i64, loc);
  head->addArgument(i64, loc);
  Value word = head->getArgument(0);
  Value end = head->getArgument(1);
  builder.setInsertionPointToStart(head);
  Value selected = load(address(merge.getSource(), word));
  cf::CondBranchOp::create(builder, loc, empty(selected), advance, update);
  builder.setInsertionPointToStart(update);
  add(word, selected);
  cf::BranchOp::create(builder, loc, advance);
  builder.setInsertionPointToStart(advance);
  Value following = arith::AddIOp::create(builder, loc, word, constant(1));
  Value more = arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::ult,
                                     following, end);
  if (grouped)
    cf::CondBranchOp::create(builder, loc, more, head,
                             ValueRange{following, end}, nextGroup,
                             ValueRange{end});
  else
    cf::CondBranchOp::create(builder, loc, more, head,
                             ValueRange{following, end}, lastWordBlock,
                             ValueRange{});

  builder.setInsertionPointToEnd(entry);
  if (!grouped) {
    cf::BranchOp::create(builder, loc, head,
                         ValueRange{constant(0), constant(span)});
    merge.erase();
    return;
  }
  cf::BranchOp::create(builder, loc, nextGroup, ValueRange{constant(0)});
  // After the whole groups, the remaining words, if any, else the last word.
  Block *scan = block();
  Block *rest = wholeEnd == span ? lastWordBlock : block();
  builder.setInsertionPointToStart(nextGroup);
  Value start = nextGroup->getArgument(0);
  Value groupsDone = arith::CmpIOp::create(
      builder, loc, arith::CmpIPredicate::uge, start, constant(wholeEnd));
  cf::CondBranchOp::create(builder, loc, groupsDone, rest, scan);

  builder.setInsertionPointToStart(scan);
  Value next = arith::AddIOp::create(builder, loc, start, constant(groupWords));
  cf::CondBranchOp::create(builder, loc, emptyWords(start, groupWords),
                           nextGroup, ValueRange{next}, head,
                           ValueRange{start, next});

  // The words [wholeEnd, span) after the last whole group, tested together
  // once; a word run ending at span has merged them.
  if (rest != lastWordBlock) {
    Block *tail = block();
    builder.setInsertionPointToStart(rest);
    Value tailDone = arith::CmpIOp::create(
        builder, loc, arith::CmpIPredicate::uge, start, constant(span));
    cf::CondBranchOp::create(builder, loc, tailDone, lastWordBlock, tail);
    builder.setInsertionPointToStart(tail);
    cf::CondBranchOp::create(builder, loc,
                             emptyWords(constant(wholeEnd), span - wholeEnd),
                             lastWordBlock, ValueRange{}, head,
                             ValueRange{constant(wholeEnd), constant(span)});
  }
  merge.erase();
}

// Keep readiness semantic until conversion. Only speculatable, effect-free
// operations may separate actions sharing one proven base and ready universe.
// In particular a ready read, ordinary load, transition, call or alias action
// ends a batch, even when its result is unused.
void materializeReadyBatches(Operation *operation,
                             const schedule::NativeGlobalLookup &globals) {
  SmallVector<SmallVector<Operation *>> batches;
  SmallVector<Block *> blocks;
  llvm::SmallPtrSet<Block *, 16> seen;
  operation->walk([&](Operation *op) {
    if (isa<schedule::NativeReadyUpdateOp, schedule::NativeReadyCommitOp>(op) &&
        seen.insert(op->getBlock()).second)
      blocks.push_back(op->getBlock());
  });
  auto baseAndCapacity = [](Operation *op) -> std::pair<Value, uint64_t> {
    if (auto update = dyn_cast<schedule::NativeReadyUpdateOp>(op))
      return {update.getBase(), update.getCapacity()};
    if (auto commit = dyn_cast<schedule::NativeReadyCommitOp>(op))
      return {commit.getBase(), commit.getCapacity()};
    return {};
  };
  auto sameBase = [&](Value a, Value b) {
    if (a == b)
      return true;
    auto lhs = a.getDefiningOp<LLVM::AddressOfOp>();
    auto rhs = b.getDefiningOp<LLVM::AddressOfOp>();
    // Distinct aliases or opaque pointers do not prove a shared base.
    return lhs && rhs && globals(lhs) && globals(lhs) == globals(rhs);
  };
  for (Block *block : blocks) {
    SmallVector<Operation *> pending;
    Value base;
    uint64_t capacity = 0;
    auto flush = [&]() {
      if (pending.size() > 1)
        batches.push_back(std::move(pending));
      pending.clear();
      base = {};
    };
    for (Operation &op : *block) {
      auto [current, count] = baseAndCapacity(&op);
      if (current) {
        if (base && (capacity != count || !sameBase(base, current)))
          flush();
        base = current;
        capacity = count;
        pending.push_back(&op);
      } else if (!isMemoryEffectFree(&op) || !isSpeculatable(&op)) {
        flush();
      }
    }
    flush();
  }
  for (const auto &batch : batches) {
    OpBuilder builder(batch.back());
    auto loc = batch.back()->getLoc();
    auto [base, capacity] = baseAndCapacity(batch.back());
    Value zero = detail::llvmConstant(builder, loc, builder.getI64Type(), 0);
    SmallVector<detail::EvalReadyWordChange> changes;
    for (Operation *op : batch) {
      if (auto update = dyn_cast<schedule::NativeReadyUpdateOp>(op))
        changes.push_back({unsigned(update.getWord()),
                           update.getConsume() ? update.getMask() : zero,
                           update.getConsume() ? zero : update.getMask()});
      else {
        auto commit = cast<schedule::NativeReadyCommitOp>(op);
        changes.push_back({unsigned(commit.getWord()), commit.getRemoveMask(),
                           commit.getAddMask()});
      }
    }
    detail::materializeEvalReadyWords(
        builder, loc, base, detail::EvalReadySetLayout(capacity), changes);
    for (Operation *op : batch)
      op->erase();
  }
}

void declareStaticTransition(ModuleOp module) {
  OpBuilder builder(module.getContext());
  auto ptr = LLVM::LLVMPointerType::get(builder.getContext());
  detail::getOrDeclareLLVMFunction(
      module, "talos_rt_v1_scheduler_static_transition",
      LLVM::LLVMVoidType::get(builder.getContext()),
      {ptr, builder.getI32Type(), builder.getI64Type(), builder.getI64Type(),
       builder.getI64Type(), builder.getI64Type(), builder.getI64Type(),
       builder.getI64Type()});
}

/// Lowers NBA batches. An unspecialized batch adds a module global and a
/// runtime declaration; `cache`, if given, stays coherent with the global.
void lowerNBABatches(Operation *operation, SymbolTableCollection *cache) {
  SmallVector<schedule::NativeNBABatchOp> batches =
      analysis::collectInWalkOrder<schedule::NativeNBABatchOp>(operation);
  for (auto batch : batches) {
    if (batch.getLayoutAttr()) {
      detail::lowerSpecializedNBABatch(batch, /*declareRuntime=*/true);
      continue;
    }
    auto module = batch->getParentOfType<ModuleOp>();
    OpBuilder builder(batch);
    auto loc = batch.getLoc();
    auto ptr = LLVM::LLVMPointerType::get(builder.getContext());
    auto i32 = builder.getI32Type();
    detail::getOrDeclareLLVMFunction(module,
                                     "talos_rt_v1_static_nba_commit_batch", i32,
                                     {ptr, ptr, i32, i32, ptr});
    SmallVector<uint32_t> roots;
    for (auto commit : batch.getBody().getOps<schedule::NativeNBACommitOp>())
      roots.push_back(commit.getRoot());
    LLVM::GlobalOp table;
    {
      SymbolTable unique(module);
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToStart(module.getBody());
      auto tensor = RankedTensorType::get({int64_t(roots.size())}, i32);
      table = LLVM::GlobalOp::create(
          builder, loc, LLVM::LLVMArrayType::get(i32, roots.size()), true,
          LLVM::Linkage::Internal, "__talos_nba_batch_roots",
          DenseIntElementsAttr::get(tensor, ArrayRef<uint32_t>(roots)), 4);
      unique.insert(table);
      // Keep a caller's cache coherent; the name is already unique.
      if (cache)
        cache->getSymbolTable(module).insert(table);
    }
    Value address = LLVM::AddressOfOp::create(builder, loc, table);
    auto call = LLVM::CallOp::create(
        builder, loc, TypeRange{i32},
        SymbolRefAttr::get(builder.getContext(),
                           "talos_rt_v1_static_nba_commit_batch"),
        ValueRange{batch.getContext(), address,
                   detail::llvmConstant(builder, loc, i32, roots.size()),
                   batch.getBarrier(), batch.getChanged()});
    batch.replaceAllUsesWith(call.getResult());
    batch.erase();
  }
}

/// Lowers the remaining actions in place. The module is touched only to
/// declare the static-transition entry, and only if `declareRuntime`.
/// Returns whether the lowered actions call the static transition.
bool materializeLocalScheduleActions(
    Operation *operation, bool coalesce, bool preserveReadiness,
    const schedule::NativeGlobalLookup &globals, bool declareRuntime) {
  if (coalesce && !preserveReadiness)
    schedule::coalesceNativeReadyUpdates(operation, globals);
  SmallVector<schedule::NativeReadyRegionOp> readyRegions;
  if (!preserveReadiness)
    readyRegions =
        analysis::collectInWalkOrder<schedule::NativeReadyRegionOp>(operation);
  for (auto region : readyRegions)
    detail::lowerNativeReadyRegion(region, globals);
  if (coalesce && !preserveReadiness)
    materializeReadyBatches(operation, globals);
  SmallVector<schedule::NativeReadyUpdateOp> updates;
  SmallVector<schedule::NativeTransitionOp> transitions;
  SmallVector<schedule::NativeReadyCommitOp> commits;
  SmallVector<schedule::NativeReadyReadOp> reads;
  SmallVector<schedule::NativeReadyMergeOp> merges;
  // One walk of the whole module collects every kind in its own walk order.
  for (Operation *op :
       analysis::collectInWalkOrder<Operation *>(operation, [&](Operation *op) {
         return isa<schedule::NativeTransitionOp>(op) ||
                (!preserveReadiness &&
                 isa<schedule::NativeReadyUpdateOp,
                     schedule::NativeReadyCommitOp, schedule::NativeReadyReadOp,
                     schedule::NativeReadyMergeOp>(op));
       })) {
    if (auto transition = dyn_cast<schedule::NativeTransitionOp>(op))
      transitions.push_back(transition);
    else if (auto update = dyn_cast<schedule::NativeReadyUpdateOp>(op))
      updates.push_back(update);
    else if (auto commit = dyn_cast<schedule::NativeReadyCommitOp>(op))
      commits.push_back(commit);
    else if (auto merge = dyn_cast<schedule::NativeReadyMergeOp>(op))
      merges.push_back(merge);
    else
      reads.push_back(cast<schedule::NativeReadyReadOp>(op));
  }
  if (declareRuntime && !transitions.empty()) {
    auto module = dyn_cast<ModuleOp>(operation);
    if (!module)
      module = operation->getParentOfType<ModuleOp>();
    declareStaticTransition(module);
  }
  for (auto read : reads) {
    OpBuilder builder(read);
    Value value = detail::loadOwnerWord(builder, read.getLoc(), read.getBase(),
                                        read.getWord());
    if (auto owner = schedule::get<schedule::Field::EvalActivationEntry>(read))
      schedule::set<schedule::Field::EvalActivationEntry>(value.getDefiningOp(),
                                                          owner);
    read.replaceAllUsesWith(value);
    read.erase();
  }
  for (auto update : updates) {
    OpBuilder builder(update);
    detail::EvalReadySetLayout layout(update.getCapacity());
    detail::materializeEvalReadyWord(builder, update.getLoc(), update.getBase(),
                                     layout, update.getWord(), update.getMask(),
                                     update.getConsume());
    update.erase();
  }
  for (auto commit : commits) {
    OpBuilder builder(commit);
    auto loc = commit.getLoc();
    detail::EvalReadySetLayout layout(commit.getCapacity());
    Value previous =
        detail::loadOwnerWord(builder, loc, commit.getBase(), commit.getWord());
    Value inverse = builder.createOrFold<arith::XOrIOp>(
        loc, commit.getRemoveMask(),
        detail::llvmConstant(builder, loc, builder.getI64Type(), UINT64_MAX));
    Value retained =
        builder.createOrFold<arith::AndIOp>(loc, previous, inverse);
    Value next =
        builder.createOrFold<arith::OrIOp>(loc, retained, commit.getAddMask());
    LLVM::StoreOp::create(builder, loc, next,
                          detail::ownerWordAddress(
                              builder, loc, commit.getBase(), commit.getWord()),
                          8);
    detail::materializeEvalReadyIndexes(builder, loc, commit.getBase(), layout,
                                        commit.getWord(), commit.getAddMask());
    commit.erase();
  }
  for (auto merge : merges)
    materializeReadyMerge(merge);
  for (auto transition : transitions) {
    OpBuilder builder(transition);
    auto call = LLVM::CallOp::create(
        builder, transition.getLoc(), TypeRange{},
        SymbolRefAttr::get(builder.getContext(),
                           "talos_rt_v1_scheduler_static_transition"),
        ValueRange{transition.getContext(),
                   detail::llvmConstant(builder, transition.getLoc(),
                                        builder.getI32Type(),
                                        transition.getStaticState()),
                   transition.getOffset(),
                   detail::llvmConstant(builder, transition.getLoc(),
                                        builder.getI64Type(),
                                        transition.getWidth()),
                   transition.getOldValue(), transition.getOldUnknown(),
                   transition.getNewValue(), transition.getNewUnknown()});
    if (auto owner = transition.getSourceOwnerAttr())
      schedule::set<schedule::Field::EvalSourceOwner>(call, owner);
    if (auto routed =
            schedule::get<schedule::Field::EvalRuntimeRoutedPublication>(
                transition))
      schedule::set<schedule::Field::EvalRuntimeRoutedPublication>(call,
                                                                   routed);
    transition.erase();
  }
  return !transitions.empty();
}

LogicalResult convertActionArithmetic(Operation *operation) {
  LLVMTypeConverter converter(operation->getContext());
  RewritePatternSet patterns(operation->getContext());
  arith::populateArithToLLVMConversionPatterns(converter, patterns);
  cf::populateControlFlowToLLVMConversionPatterns(converter, patterns);
  ConversionTarget target(*operation->getContext());
  target.addLegalDialect<LLVM::LLVMDialect>();
  target.addIllegalDialect<arith::ArithDialect, cf::ControlFlowDialect>();
  target.markUnknownOpDynamicallyLegal([](Operation *) { return true; });
  return applyPartialConversion(operation, target, std::move(patterns));
}

/// Lowers each function of `module` independently, as the serial module-wide
/// lowering would: only batches and runtime declarations touch the module, so
/// they run first; each worker then rewrites and converts its own function.
/// Returns nothing, before any change, if an operation outside the functions
/// is not already LLVM IR.
std::optional<LogicalResult> lowerModuleActionsInParallel(ModuleOp module) {
  MLIRContext *context = module.getContext();
  SmallVector<LLVM::LLVMFuncOp> functions;
  SmallVector<Operation *> others;
  for (Operation &operation : *module.getBody()) {
    if (auto function = dyn_cast<LLVM::LLVMFuncOp>(operation)) {
      if (!function.isExternal())
        functions.push_back(function);
    } else {
      others.push_back(&operation);
    }
  }
  std::atomic<bool> foreign = false;
  analysis::parallelForChunked(context, others.size(), [&](size_t index) {
    others[index]->walk([&](Operation *nested) {
      if (isa_and_nonnull<LLVM::LLVMDialect>(nested->getDialect()))
        return WalkResult::advance();
      foreign = true;
      return WalkResult::interrupt();
    });
  });
  if (foreign)
    return std::nullopt;
  lowerNBABatches(module, /*cache=*/nullptr);
  std::atomic<bool> transitions = false;
  analysis::parallelForChunked(context, functions.size(), [&](size_t index) {
    if (functions[index]
            .walk([](schedule::NativeTransitionOp) {
              return WalkResult::interrupt();
            })
            .wasInterrupted())
      transitions = true;
  });
  if (transitions)
    declareStaticTransition(module);
  // Workers add or remove no symbols.
  SymbolTable symbols(module);
  schedule::NativeGlobalLookup globals(symbols);
  std::atomic<bool> converted = true;
  analysis::parallelForChunked(context, functions.size(), [&](size_t index) {
    LLVM::LLVMFuncOp function = functions[index];
    materializeLocalScheduleActions(function, /*coalesce=*/true,
                                    /*preserveReadiness=*/false, globals,
                                    /*declareRuntime=*/false);
    bool converts = function
                        .walk([](Operation *operation) {
                          return isa_and_nonnull<arith::ArithDialect,
                                                 cf::ControlFlowDialect>(
                                     operation->getDialect())
                                     ? WalkResult::interrupt()
                                     : WalkResult::advance();
                        })
                        .wasInterrupted();
    if (converts && failed(convertActionArithmetic(function)))
      converted = false;
  });
  return success(converted);
}
} // namespace

void materializeNativeScheduleActions(Operation *operation, bool coalesce,
                                      bool preserveReadiness,
                                      SymbolTableCollection *cache) {
  SymbolTableCollection local;
  lowerNBABatches(operation, cache);
  materializeLocalScheduleActions(operation, coalesce, preserveReadiness,
                                  cache ? *cache : local,
                                  /*declareRuntime=*/true);
}

FailureOr<NativeFunctionActionLowering> lowerNativeFunctionScheduleActions(
    LLVM::LLVMFuncOp function, const schedule::NativeGlobalLookup &globals) {
  NativeFunctionActionLowering lowering;
  SmallVector<schedule::NativeNBABatchOp> batches =
      analysis::collectInWalkOrder<schedule::NativeNBABatchOp>(function);
  // An unspecialized batch adds its root table to the module.
  if (llvm::any_of(batches, [](schedule::NativeNBABatchOp batch) {
        return !batch.getLayoutAttr();
      }))
    return lowering;
  for (auto batch : batches)
    detail::lowerSpecializedNBABatch(batch, /*declareRuntime=*/false);
  lowering.callsBatchRuntime = !batches.empty();
  lowering.callsStaticTransition = materializeLocalScheduleActions(
      function, /*coalesce=*/true, /*preserveReadiness=*/false, globals,
      /*declareRuntime=*/false);
  if (failed(convertActionArithmetic(function)))
    return failure();
  lowering.lowered = true;
  return lowering;
}

void declareNativeFunctionActionRuntime(
    ModuleOp module, const NativeFunctionActionLowering &lowering) {
  // In the order lowerNativeScheduleActionsToLLVM declares them.
  if (lowering.callsBatchRuntime)
    detail::declareSpecializedNBABatchRuntime(module);
  if (lowering.callsStaticTransition)
    declareStaticTransition(module);
}

LogicalResult lowerNativeScheduleActionsToLLVM(Operation *operation,
                                               SymbolTableCollection *symbols) {
  if (auto module = dyn_cast<ModuleOp>(operation); module && !symbols)
    if (std::optional<LogicalResult> lowered =
            lowerModuleActionsInParallel(module))
      return *lowered;
  materializeNativeScheduleActions(operation, /*coalesce=*/true,
                                   /*preserveReadiness=*/false, symbols);
  return convertActionArithmetic(operation);
}

#define GEN_PASS_DEF_CONVERTNATIVESCHEDULEACTIONSTOLLVMPASS
#include "talos/Conversion/Passes.h.inc"
namespace {
struct ConvertNativeScheduleActionsToLLVMPass
    : impl::ConvertNativeScheduleActionsToLLVMPassBase<
          ConvertNativeScheduleActionsToLLVMPass> {
  using ConvertNativeScheduleActionsToLLVMPassBase::
      ConvertNativeScheduleActionsToLLVMPassBase;
  void runOnOperation() override {
    materializeNativeScheduleActions(getOperation(), coalesce);
  }
};
} // namespace
} // namespace talos
