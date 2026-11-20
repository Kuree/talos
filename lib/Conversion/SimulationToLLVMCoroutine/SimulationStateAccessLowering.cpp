//===- SimulationStateAccessLowering.cpp - Native state access patterns --===//

#include "NativeStateAccess.h"
#include "SimulationLocalStorageLowering.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Analysis/NativeStorageLayout.h"
#include "talos/Conversion/SimulationToStandard.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

#include <limits>
#include <map>

using namespace mlir;

namespace talos::detail {
namespace {

// Canonical padding is not a language value. Invalid aggregate reads also
// need the per-member defaults from IEEE 1800-2023 Table 7-1.
Value maskStoragePlane(OpBuilder &builder, Location location, Value bits,
                       Type type, bool unknown) {
  APInt mask = unknown ? analysis::getDefaultUnknownMask(type)
                       : analysis::getLogicalStorageMask(type);
  if (mask.isAllOnes())
    return bits;
  return arith::AndIOp::create(
      builder, location, bits,
      arith::ConstantOp::create(builder, location,
                                builder.getIntegerAttr(bits.getType(), mask)));
}

Value loadCurrentRuntimeContext(ConversionPatternRewriter &rewriter,
                                Location location) {
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  Value address = LLVM::AddressOfOp::create(rewriter, location, pointer,
                                            "__talos_current_context");
  return LLVM::LoadOp::create(rewriter, location, pointer, address, 8);
}

void reportRuntimeControlStatus(ConversionPatternRewriter &rewriter,
                                Location location, Value context,
                                Value status) {
  LLVM::CallOp::create(
      rewriter, location, TypeRange{},
      SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
      ValueRange{context, status});
}

bool useTwoStateSpecialization(Operation *operation, bool moduleWide) {
  if (moduleWide)
    return true;
  return ::talos::schedule::has<
      ::talos::schedule::Field::EvalInductiveTwoStateAccess>(operation);
}

/// A read whose location is known on its executing path observes a zero
/// unknown plane; only its value plane needs to be loaded.
bool readsKnownLocation(Operation *operation, bool moduleWide) {
  return useTwoStateSpecialization(operation, moduleWide) ||
         ::talos::schedule::has<::talos::schedule::Field::NativeKnownRead>(
             operation);
}

Value allocateBulkPlane(ConversionPatternRewriter &rewriter, Location location,
                        uint64_t width) {
  return entryAlloca(rewriter, location, rewriter.getI8Type(), (width + 7) / 8,
                     1);
}

Value loadBulkStatePlane(ConversionPatternRewriter &rewriter, Location location,
                         Value handle, uint64_t width,
                         schedule::StatePlane plane, bool unknownFallback,
                         uint64_t stateBitCount,
                         const NativeStateLayout *directLayout,
                         bool assumeClean) {
  Type i32 = rewriter.getI32Type();
  Type i64 = rewriter.getI64Type();
  Value output = allocateBulkPlane(rewriter, location, width);
  std::optional<DirectStaticStateRange> range =
      resolveDirectStaticStateRange(handle, width, directLayout);
  if (range && (!range->guarded || assumeClean) && range->offset % 8 == 0) {
    LLVM::MemcpyOp::create(
        rewriter, location, output,
        schedule::NativeStateWindowAddressOp::create(
            rewriter, location, plane, Value(), range->offset / 8),
        llvmConstant(rewriter, location, i64, (width + 7) / 8), false);
    return output;
  }
  Value base = detail::createStatePlaneAddress(rewriter, location, plane);
  Value context = loadCurrentRuntimeContext(rewriter, location);
  LLVM::CallOp::create(
      rewriter, location, TypeRange{i32},
      SymbolRefAttr::get(rewriter.getContext(),
                         "talos_rt_v1_native_state_load_plane"),
      ValueRange{context, base,
                 llvmConstant(rewriter, location, i64, stateBitCount), handle,
                 llvmConstant(rewriter, location, i64, width),
                 llvmConstant(rewriter, location, i32,
                              plane == schedule::StatePlane::Unknown ? 1 : 0),
                 llvmConstant(rewriter, location, i32, unknownFallback ? 1 : 0),
                 output});
  return output;
}

void storeBulkStatePlane(ConversionPatternRewriter &rewriter, Location location,
                         Value handle, Value input, uint64_t width,
                         schedule::StatePlane plane, uint64_t stateBitCount,
                         Value changed, bool continuous) {
  Type i32 = rewriter.getI32Type();
  Type i64 = rewriter.getI64Type();
  Value base = detail::createStatePlaneAddress(rewriter, location, plane);
  Value context = loadCurrentRuntimeContext(rewriter, location);
  LLVM::CallOp::create(
      rewriter, location, TypeRange{i32},
      SymbolRefAttr::get(rewriter.getContext(),
                         continuous
                             ? "talos_rt_v1_native_state_store_continuous_plane"
                             : "talos_rt_v1_native_state_store_plane"),
      ValueRange{context, base,
                 llvmConstant(rewriter, location, i64, stateBitCount), handle,
                 llvmConstant(rewriter, location, i64, width),
                 llvmConstant(rewriter, location, i32,
                              plane == schedule::StatePlane::Unknown ? 1 : 0),
                 input, changed});
}

// Copy a canonical byte buffer directly into a certified state plane. Only
// the final partial byte needs a read/modify/write; the rest remains memcpy.
// Continuous roots also retain their contribution for later force/release.
bool tryStoreBulkDirect(ConversionPatternRewriter &rewriter, Location location,
                        Value handle, Value input, uint64_t width,
                        schedule::StatePlane plane,
                        const NativeStateLayout *layout, bool assumeClean,
                        bool continuous) {
  auto range = resolveDirectStaticStateRange(handle, width, layout);
  if (!range || range->offset % 8 || (range->guarded && !assumeClean) ||
      (continuous && range->guarded && !layout->directContinuous))
    return false;
  IntegerType i8 = rewriter.getI8Type();
  auto copy = [&](schedule::StatePlane target, bool mask = false) {
    Value destination = schedule::NativeStateWindowAddressOp::create(
        rewriter, location, target, Value(), range->offset / 8);
    Value bytes =
        llvmConstant(rewriter, location, rewriter.getI64Type(), width / 8);
    Value ones = llvmConstant(rewriter, location, i8, 255);
    if (mask)
      LLVM::MemsetOp::create(rewriter, location, destination, ones, bytes,
                             false);
    else
      LLVM::MemcpyOp::create(rewriter, location, destination, input, bytes,
                             false);
    if (unsigned tail = width % 8) {
      // The input may borrow a state plane's window too.
      Value old = createLoadAt(rewriter, location, i8, destination, Value(),
                               width / 8, 1);
      Value value = mask ? ones
                         : createLoadAt(rewriter, location, i8, input, Value(),
                                        width / 8, 1);
      Value bits = llvmConstant(rewriter, location, i8, (1u << tail) - 1);
      Value delta = arith::XOrIOp::create(rewriter, location, old, value);
      delta = arith::AndIOp::create(rewriter, location, delta, bits);
      Value merged = arith::XOrIOp::create(rewriter, location, old, delta);
      createStoreAt(rewriter, location, merged, destination, Value(), width / 8,
                    1);
    }
  };
  // A continuous root retains its contribution for a later release (IEEE
  // 1800-2023 10.6.2).
  if (continuous && layout->directContinuous) {
    copy(plane == schedule::StatePlane::Unknown
             ? schedule::StatePlane::ContributionUnknown
             : schedule::StatePlane::ContributionValue);
    if (plane == schedule::StatePlane::Value)
      copy(schedule::StatePlane::ContributionMask, true);
  }
  copy(plane);
  return true;
}

void notifyBulkSignal(ConversionPatternRewriter &rewriter, Location location,
                      Value handle, uint64_t width, Value oldValue,
                      Value oldUnknown, Value newValue, Value newUnknown,
                      schedule::SourceOwnerAttr sourceOwner = {},
                      bool nbaEquivalent = false) {
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  auto pointerOrNull = [&](Value value) {
    return value
               ? value
               : LLVM::ZeroOp::create(rewriter, location, pointer).getResult();
  };
  auto call = LLVM::CallOp::create(
      rewriter, location, TypeRange{},
      SymbolRefAttr::get(rewriter.getContext(),
                         "talos_rt_v1_scheduler_signal_transition"),
      ValueRange{loadCurrentRuntimeContext(rewriter, location), handle,
                 llvmConstant(rewriter, location, rewriter.getI64Type(), width),
                 oldValue, pointerOrNull(oldUnknown), newValue,
                 pointerOrNull(newUnknown)});
  if (sourceOwner)
    ::talos::schedule::set<schedule::metadata::evalSourceOwner>(call,
                                                                sourceOwner);
  // Its machine-word slices inherit the mark (see
  // normalizeGeneratedWideTransitions).
  if (nbaEquivalent)
    ::talos::schedule::set<::talos::schedule::Field::EvalNbaEquivalentStore>(
        call, rewriter.getUnitAttr());
}

class BulkRefCopyConversion final
    : public OpConversionPattern<sim::SimRefCopyOp> {
public:
  BulkRefCopyConversion(const TypeConverter &converter, MLIRContext *context,
                        uint64_t stateBitCount,
                        const NativeStateLayout *directLayout,
                        bool experimentalTwoState)
      : OpConversionPattern(converter, context, PatternBenefit(2)),
        stateBitCount(stateBitCount), directLayout(directLayout),
        experimentalTwoState(experimentalTwoState) {}

  LogicalResult
  matchAndRewrite(sim::SimRefCopyOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type valueType =
        cast<sim::RefType>(op.getSource().getType()).getElementType();
    std::optional<unsigned> width = nativeStateWidth(valueType);
    if (!width || *width <= 64 || adaptor.getSource().size() != 1 ||
        adaptor.getDestination().size() != 1)
      return failure();

    Value source = adaptor.getSource().front();
    Value destination = adaptor.getDestination().front();

    Location location = op.getLoc();
    // Wide load/store fusion preserves the store's path certificate. Like a
    // scalar known store, its RHS and old destination have zero unknown bits
    // (IEEE 1800-2023 6.3.1/4.6); leave that memory plane untouched.
    bool twoState = useTwoStateSpecialization(op, experimentalTwoState) ||
                    schedule::has<schedule::Field::NativeKnownStore>(op);
    bool fourState = containsLogic(valueType) && !twoState;
    sim::SimFuncOp function = op->getParentOfType<sim::SimFuncOp>();
    sim::EntryKind entryKind = function.getEntryKind();
    bool continuous = sim::has<sim::metadata::ContinuousStore>(op) ||
                      entryKind == sim::EntryKind::Continuous ||
                      entryKind == sim::EntryKind::PortInput ||
                      entryKind == sim::EntryKind::PortOutput;
    bool sourceAssumeClean = native::has<native::BulkCopySourceAssumeClean>(op);

    Value sourceValue = loadBulkStatePlane(
        rewriter, location, source, *width, schedule::StatePlane::Value, false,
        stateBitCount, directLayout, sourceAssumeClean);
    Value sourceUnknown;
    if (fourState)
      sourceUnknown = loadBulkStatePlane(
          rewriter, location, source, *width, schedule::StatePlane::Unknown,
          true, stateBitCount, directLayout, sourceAssumeClean);
    Value oldValue = loadBulkStatePlane(rewriter, location, destination, *width,
                                        schedule::StatePlane::Value, false,
                                        stateBitCount, directLayout, false);
    Value oldUnknown;
    if (fourState)
      oldUnknown = loadBulkStatePlane(rewriter, location, destination, *width,
                                      schedule::StatePlane::Unknown, true,
                                      stateBitCount, directLayout, false);

    Value changed = entryAlloca(rewriter, location, rewriter.getI8Type(), 1, 1);
    storeBulkStatePlane(rewriter, location, destination, sourceValue, *width,
                        schedule::StatePlane::Value, stateBitCount, changed,
                        continuous);
    if (fourState)
      storeBulkStatePlane(rewriter, location, destination, sourceUnknown,
                          *width, schedule::StatePlane::Unknown, stateBitCount,
                          changed, continuous);

    // A generic packed store may be partially masked by a force or procedural
    // assign. Reload the visible destination planes before publication, just
    // like the scalar lowering required by IEEE 1800-2017 10.6.1-10.6.2.
    Value newValue = loadBulkStatePlane(rewriter, location, destination, *width,
                                        schedule::StatePlane::Value, false,
                                        stateBitCount, directLayout, false);
    Value newUnknown;
    if (fourState)
      newUnknown = loadBulkStatePlane(rewriter, location, destination, *width,
                                      schedule::StatePlane::Unknown, true,
                                      stateBitCount, directLayout, false);
    notifyBulkSignal(
        rewriter, location, destination, *width, oldValue, oldUnknown,
        newValue, newUnknown, /*sourceOwner=*/{},
        ::talos::schedule::has<
            ::talos::schedule::Field::EvalNbaEquivalentStore>(op));
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
};

class KnownValueConversion final
    : public OpConversionPattern<schedule::NativeKnownValueOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(schedule::NativeKnownValueOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto planes = adaptor.getInput();
    if (planes.size() == 1) {
      rewriter.replaceOpWithNewOp<arith::ConstantOp>(
          op, rewriter.getI1Type(), rewriter.getBoolAttr(true));
      return success();
    }
    if (planes.size() != 2 || !isa<IntegerType>(planes[1].getType()))
      return failure();
    Value zero = arith::ConstantOp::create(
        rewriter, op.getLoc(), planes[1].getType(),
        rewriter.getIntegerAttr(planes[1].getType(), 0));
    rewriter.replaceOpWithNewOp<arith::CmpIOp>(op, arith::CmpIPredicate::eq,
                                               planes[1], zero);
    return success();
  }
};

} // namespace

bool branchesOnKnownRoots(cf::CondBranchOp branch) {
  auto gate =
      branch.getCondition().getDefiningOp<schedule::NativeKnownRootsOp>();
  return gate && gate->hasOneUse() && gate->getNextNode() == branch;
}

namespace {
/// The (word, mask) pairs of the unknown summary `gate` tests, as planning
/// recorded them (assignUnknownSummary): empty when every root is two-state
/// and cannot hold x or z (IEEE 1800-2023 6.11.2), so the test holds;
/// failure when the test never holds and the four-state body always runs.
FailureOr<SmallVector<std::pair<uint64_t, uint64_t>>>
knownRootsSummaryWords(schedule::NativeKnownRootsOp gate) {
  auto pairs = schedule::get<schedule::Field::NativeKnownSummaryWords>(gate);
  if (!pairs || pairs.size() % 2)
    return failure();
  SmallVector<std::pair<uint64_t, uint64_t>> words;
  for (size_t index = 0; index != size_t(pairs.size()); index += 2)
    words.emplace_back(pairs[index], pairs[index + 1]);
  return words;
}

/// The gate's backoff slot, when planning allotted one.
IntegerAttr knownRootsBackoff(schedule::NativeKnownRootsOp gate,
                              const NativeStateLayout &layout) {
  auto slot = schedule::get<schedule::Field::NativeKnownGate>(gate);
  return slot && slot.getValue().ult(layout.unknownSummaryGates)
             ? slot
             : IntegerAttr{};
}

/// Where each answer of a summary test goes. A constant answer takes the
/// edge `edge` returns; `dynamic` terminates the refresh block with the
/// runtime's answer.
struct KnownRootsExits {
  function_ref<std::pair<Block *, SmallVector<Value>>(bool)> edge;
  function_ref<void(Value)> dynamic;
};

/// Test the unknown summary bits of whole storage roots, one summary word at
/// a time, at the insertion point, which then ends its block. New blocks go
/// before `blocks`. A set bit may be stale after the root became known again:
/// the runtime then rescans the gate's dirty roots before answering. After a
/// failed rescan the gate fails the number of tests its backoff state counts
/// without calling. A stale bit or a backoff only fails the test, and a
/// failed test runs the four-state body, which is exact for x and z (IEEE
/// 1800-2023 6.3.1). The test reads and writes only compiler-owned summary
/// and backoff state: it schedules no event and changes no design value
/// (4.4.2, 4.5).
///
///   head:     %dirty = or(summary[w] & mask_w ...)
///             cond_br %dirty == 0, <true edge>, ^refresh
///   ^refresh: %state = backoff[g]
///             cond_br trunc(%state) != 0, ^wait, ^call
///   ^wait:    backoff[g] = %state - 1; <false edge>
///   ^call:    <refresh_unknown_summary(ctx, pairs, &backoff[g]) != 0>
void emitKnownRootsTest(ConversionPatternRewriter &rewriter, Location location,
                        ArrayRef<std::pair<uint64_t, uint64_t>> words,
                        IntegerAttr backoffSlot, Region::iterator blocks,
                        KnownRootsExits exits) {
  Type i64 = rewriter.getI64Type();
  Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
  Value summary = LLVM::AddressOfOp::create(rewriter, location, pointer,
                                            unknownSummaryName);
  Value dirty;
  for (auto [word, mask] : words) {
    Value bits =
        LLVM::LoadOp::create(rewriter, location, i64,
                             byteGEP(rewriter, location, summary, 8 * word), 8);
    bits = LLVM::AndOp::create(rewriter, location, bits,
                               llvmConstant(rewriter, location, i64, mask));
    dirty =
        dirty ? LLVM::OrOp::create(rewriter, location, dirty, bits).getResult()
              : bits;
  }
  Value clean =
      LLVM::ICmpOp::create(rewriter, location, LLVM::ICmpPredicate::eq, dirty,
                           llvmConstant(rewriter, location, i64, 0));

  Block *head = rewriter.getInsertionBlock();
  Block::iterator headPoint = rewriter.getInsertionPoint();
  Region *region = head->getParent();
  Block *refresh = rewriter.createBlock(region, blocks);
  Block *wait = rewriter.createBlock(region, blocks);
  Block *call = rewriter.createBlock(region, blocks);
  rewriter.setInsertionPoint(head, headPoint);
  auto [known, knownOperands] = exits.edge(true);
  markLikelyTrue(cf::CondBranchOp::create(
      rewriter, location, clean, known, knownOperands, refresh, ValueRange{}));
  rewriter.setInsertionPointToEnd(refresh);
  Value backoff = byteGEP(rewriter, location,
                          LLVM::AddressOfOp::create(rewriter, location, pointer,
                                                    unknownSummaryBackoffName),
                          8 * backoffSlot.getValue().getZExtValue());
  Value state = LLVM::LoadOp::create(rewriter, location, i64, backoff, 8);
  Value waiting = LLVM::ICmpOp::create(
      rewriter, location, LLVM::ICmpPredicate::ne,
      LLVM::TruncOp::create(rewriter, location, rewriter.getI32Type(), state),
      llvmConstant(rewriter, location, rewriter.getI32Type(), 0));
  markLikelyTrue(cf::CondBranchOp::create(rewriter, location, waiting, wait,
                                          ValueRange{}, call, ValueRange{}));
  rewriter.setInsertionPointToEnd(wait);
  LLVM::StoreOp::create(
      rewriter, location,
      LLVM::SubOp::create(rewriter, location, state,
                          llvmConstant(rewriter, location, i64, 1)),
      backoff, 8);
  auto [unknown, unknownOperands] = exits.edge(false);
  cf::BranchOp::create(rewriter, location, unknown, unknownOperands);
  rewriter.setInsertionPointToEnd(call);
  // The (word, mask) pairs the runtime rescans; this path is cold.
  Value pairs = entryAlloca(rewriter, location, i64, 2 * words.size(), 8);
  unsigned index = 0;
  for (auto [word, mask] : words)
    for (uint64_t element : {word, mask})
      LLVM::StoreOp::create(rewriter, location,
                            llvmConstant(rewriter, location, i64, element),
                            byteGEP(rewriter, location, pairs, 8 * index++), 8);
  Value refreshed =
      LLVM::CallOp::create(
          rewriter, location, TypeRange{rewriter.getI32Type()},
          "talos_rt_v1_native_state_refresh_unknown_summary",
          ValueRange{loadCurrentRuntimeContext(rewriter, location), pairs,
                     llvmConstant(rewriter, location, i64, words.size()),
                     backoff})
          .getResult();
  exits.dynamic(LLVM::ICmpOp::create(
      rewriter, location, LLVM::ICmpPredicate::ne, refreshed,
      llvmConstant(rewriter, location, rewriter.getI32Type(), 0)));
}

/// A summary test used as a value merges its answers in one block argument.
class KnownRootsConversion final
    : public OpConversionPattern<schedule::NativeKnownRootsOp> {
public:
  KnownRootsConversion(const TypeConverter &converter, MLIRContext *context,
                       const NativeStateLayout &layout)
      : OpConversionPattern(converter, context), layout(layout) {}

  LogicalResult
  matchAndRewrite(schedule::NativeKnownRootsOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Location location = op.getLoc();
    Type i1 = rewriter.getI1Type();
    auto words = knownRootsSummaryWords(op);
    if (failed(words) || words->empty()) {
      rewriter.replaceOpWithNewOp<arith::ConstantOp>(
          op, i1, rewriter.getBoolAttr(succeeded(words)));
      return success();
    }
    IntegerAttr backoffSlot = knownRootsBackoff(op, layout);
    if (!backoffSlot)
      return rewriter.notifyMatchFailure(op, "gate without backoff state");
    Block *head = rewriter.getInsertionBlock();
    Block *done = rewriter.splitBlock(head, rewriter.getInsertionPoint());
    BlockArgument known = done->addArgument(i1, location);
    rewriter.setInsertionPointToEnd(head);
    auto edge = [&](bool answer) -> std::pair<Block *, SmallVector<Value>> {
      return {done,
              {arith::ConstantOp::create(rewriter, location, i1,
                                         rewriter.getBoolAttr(answer))
                   .getResult()}};
    };
    auto dynamic = [&](Value answer) {
      cf::BranchOp::create(rewriter, location, done, ValueRange{answer});
    };
    emitKnownRootsTest(rewriter, location, *words, backoffSlot,
                       done->getIterator(), {edge, dynamic});
    rewriter.replaceOp(op, known);
    return success();
  }

private:
  const NativeStateLayout &layout;
};

/// A branch on a summary test takes each answer's edge straight to the
/// successor it selects. Merging the answers first would leave a block that
/// only tests a constant argument on two of its three incoming edges.
///
/// Only control flow changes: each answer selects the same successor as the
/// merged form. The two-state copy runs only when every gated root holds no x
/// or z beyond its steady pattern, where 0/1 evaluation is exact (IEEE
/// 1800-2023 6.3.1, 6.11.2); otherwise the four-state body runs. Either body
/// executes the activation's statements and nonblocking assignments in source
/// order (4.6 a, b).
class KnownRootsBranchConversion final
    : public OpConversionPattern<cf::CondBranchOp> {
public:
  KnownRootsBranchConversion(const TypeConverter &converter,
                             MLIRContext *context,
                             const NativeStateLayout &layout)
      // Above the generic branch conversion, which would keep the test as a
      // value.
      : OpConversionPattern(converter, context, /*benefit=*/3), layout(layout) {
  }

  LogicalResult
  matchAndRewrite(cf::CondBranchOp branch, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (!branchesOnKnownRoots(branch))
      return failure();
    auto gate =
        branch.getCondition().getDefiningOp<schedule::NativeKnownRootsOp>();
    auto words = knownRootsSummaryWords(gate);
    IntegerAttr backoffSlot = knownRootsBackoff(gate, layout);
    // Fail before any change: the test then stays legal with nothing to
    // lower it, and conversion reports it.
    if (succeeded(words) && !words->empty() && !backoffSlot)
      return gate.emitOpError("has no unknown summary backoff state");
    FailureOr<Block *> trueDest = convertDestinationBlockArguments(
        branch.getTrueDest(), *getTypeConverter(), rewriter);
    if (failed(trueDest))
      return failure();
    FailureOr<Block *> falseDest =
        branch.getFalseDest() == branch.getTrueDest()
            ? trueDest
            : convertDestinationBlockArguments(branch.getFalseDest(),
                                               *getTypeConverter(), rewriter);
    if (failed(falseDest))
      return failure();
    SmallVector<Value> trueOperands = flatten(adaptor.getTrueDestOperands());
    SmallVector<Value> falseOperands = flatten(adaptor.getFalseDestOperands());
    ArrayRef<int32_t> weights =
        branch.getBranchWeights().value_or(ArrayRef<int32_t>{});
    Location location = branch.getLoc();
    auto select = [&](Value condition) {
      auto selected = cf::CondBranchOp::create(
          rewriter, location, condition, *trueDest, trueOperands, *falseDest,
          falseOperands, weights);
      selected->setDiscardableAttrs(branch->getDiscardableAttrDictionary());
    };
    rewriter.setInsertionPoint(branch);
    if (failed(words) || words->empty()) {
      // Keep both edges: the other successor may have no other predecessor,
      // and region simplification removes it with the constant branch.
      select(arith::ConstantOp::create(rewriter, location, rewriter.getI1Type(),
                                       rewriter.getBoolAttr(succeeded(words))));
    } else {
      auto edge = [&](bool answer) -> std::pair<Block *, SmallVector<Value>> {
        return answer ? std::pair(*trueDest, trueOperands)
                      : std::pair(*falseDest, falseOperands);
      };
      emitKnownRootsTest(rewriter, gate.getLoc(), *words, backoffSlot,
                         std::next(branch->getBlock()->getIterator()),
                         {edge, select});
    }
    rewriter.eraseOp(branch);
    rewriter.eraseOp(gate);
    return success();
  }

private:
  const NativeStateLayout &layout;
};

class RefLoadConversion final : public OpConversionPattern<sim::SimRefLoadOp> {
public:
  RefLoadConversion(
      const TypeConverter &converter, MLIRContext *context,
      uint64_t stateBitCount, const NativeStateLayout *directLayout,
      bool experimentalTwoState,
      const DenseMap<Operation *, NativeStateAccessInfo> &stateAccesses,
      const LocalStorageLowering *locals, const NativeStateLayout *layout)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        directLayout(directLayout), experimentalTwoState(experimentalTwoState),
        stateAccesses(stateAccesses), locals(locals), layout(layout) {}

  /// The unknown plane a value-only read observes: its root's steady pattern
  /// (`simulation.steady_unknown`), which the root's clear summary bit
  /// guarantees.
  APInt knownReadUnknown(sim::SimRefLoadOp op, Value handle,
                         unsigned width) const {
    APInt unknown(width, 0);
    if (!layout ||
        !::talos::schedule::has<::talos::schedule::Field::NativeKnownRead>(op))
      return unknown;
    std::optional<uint64_t> value = resolveCFGConstantInteger(handle);
    talos_rt_stable_handle_v1 decoded{};
    if (!value || !talos_rt_stable_handle_decode(*value, &decoded) ||
        decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset < 0)
      return unknown;
    return layout->getSteadyUnknown(decoded.id, uint64_t(decoded.offset),
                                    width);
  }

  LogicalResult
  matchAndRewrite(sim::SimRefLoadOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type resultType = op.getResult().getType();
    bool twoState = readsKnownLocation(op, experimentalTwoState);
    auto proof = stateAccesses.find(op);
    const NativeStateAccessInfo *access =
        proof == stateAccesses.end() ? nullptr : &proof->second;
    std::optional<unsigned> width = nativeStateWidth(resultType);
    if (!width || adaptor.getReference().size() != 1)
      return failure();
    IntegerType plane = rewriter.getIntegerType(*width);
    bool assumeClean =
        ::talos::schedule::has<assumeCleanSpecializationAttr>(op);
    if (locals && locals->isMemoryValue(op.getResult())) {
      auto range = resolveDirectStaticStateRange(adaptor.getReference().front(),
                                                 *width, directLayout);
      // A memory value borrows its root's window of the plane in place.
      auto read = [&](schedule::StatePlane plane) -> Value {
        if (locals->canBorrowMemory(op.getResult()) && range &&
            range->offset % 8 == 0 && (!range->guarded || assumeClean))
          return schedule::NativeStateWindowAddressOp::create(
              rewriter, op.getLoc(), plane, Value(), range->offset / 8);
        return loadBulkStatePlane(rewriter, op.getLoc(),
                                  adaptor.getReference().front(), *width, plane,
                                  plane == schedule::StatePlane::Unknown,
                                  stateBitCount, directLayout, assumeClean);
      };
      SmallVector<Value> buffers{read(schedule::StatePlane::Value)};
      if (containsLogic(resultType)) {
        bool valueOnlyUsers =
            llvm::all_of(op.getResult().getUsers(), [&](Operation *user) {
              return isa<sim::SimRefStoreOp>(user) &&
                     (useTwoStateSpecialization(user, experimentalTwoState) ||
                      schedule::has<schedule::Field::NativeKnownStore>(user));
            });
        bool adjacentStore =
            op->hasOneUse() && op->getNextNode() == *op->getUsers().begin();
        if (twoState && valueOnlyUsers &&
            (locals->canBorrowMemory(op.getResult()) || adjacentStore) &&
            range && range->offset % 8 == 0 &&
            (!range->guarded || assumeClean)) {
          // These stores never consume the unknown buffer. Borrow its stable
          // address instead of generating a disposable alloca/memset. This is
          // the same snapshot/lifetime proof used for the value plane above,
          // or a sole adjacent known store, which leaves these bits unchanged
          // (IEEE 1800-2023 4.6). No unknown-plane memory is accessed.
          buffers.push_back(schedule::NativeStateWindowAddressOp::create(
              rewriter, op.getLoc(), schedule::StatePlane::Unknown, Value(),
              range->offset / 8));
        } else if (twoState) {
          Value buffer = allocateBulkPlane(rewriter, op.getLoc(), *width);
          LLVM::MemsetOp::create(
              rewriter, op.getLoc(), buffer,
              llvmConstant(rewriter, op.getLoc(), rewriter.getI8Type(), 0),
              llvmConstant(rewriter, op.getLoc(), rewriter.getI64Type(),
                           (*width + 7) / 8),
              false);
          APInt pattern =
              knownReadUnknown(op, adaptor.getReference().front(), *width);
          for (unsigned byte = 0; byte * 8 < *width; ++byte)
            if (uint64_t bits = pattern.extractBitsAsZExtValue(
                    std::min(8u, *width - byte * 8), byte * 8))
              LLVM::StoreOp::create(
                  rewriter, op.getLoc(),
                  llvmConstant(rewriter, op.getLoc(), rewriter.getI8Type(),
                               bits),
                  byteGEP(rewriter, op.getLoc(), buffer, byte), 1);
          buffers.push_back(buffer);
        } else {
          buffers.push_back(read(schedule::StatePlane::Unknown));
        }
      }
      rewriter.replaceOpWithMultiple(op, {ValueRange(buffers)});
      return success();
    }
    Value guardedPermission;
    if (auto range = resolveDirectStaticStateRange(
            adaptor.getReference().front(), *width, directLayout);
        range && range->guarded && !assumeClean)
      guardedPermission = staticSpecializationGuard(
          rewriter, op.getLoc(), range->staticID, TALOS_RT_STATIC_ROOT_READ);
    Value value =
        loadStatePlane(rewriter, op.getLoc(), adaptor.getReference().front(),
                       plane, schedule::StatePlane::Value, false, stateBitCount,
                       directLayout, guardedPermission, assumeClean, access);
    value = maskStoragePlane(rewriter, op.getLoc(), value, resultType, false);
    if (isa<FloatType>(resultType))
      value =
          arith::BitcastOp::create(rewriter, op.getLoc(), resultType, value);
    SmallVector<Value> converted{value};
    if (containsLogic(resultType)) {
      Value unknown =
          twoState
              ? arith::ConstantOp::create(
                    rewriter, op.getLoc(), plane,
                    rewriter.getIntegerAttr(
                        plane, knownReadUnknown(
                                   op, adaptor.getReference().front(), *width)))
                    .getResult()
              : loadStatePlane(
                    rewriter, op.getLoc(), adaptor.getReference().front(),
                    plane, schedule::StatePlane::Unknown, true, stateBitCount,
                    directLayout, guardedPermission, assumeClean, access);
      converted.push_back(
          maskStoragePlane(rewriter, op.getLoc(), unknown, resultType, true));
    }
    SmallVector<ValueRange> replacements{ValueRange(converted)};
    rewriter.replaceOpWithMultiple(op, replacements);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
  const DenseMap<Operation *, NativeStateAccessInfo> &stateAccesses;
  const LocalStorageLowering *locals;
  const NativeStateLayout *layout;
};

class RefStoreConversion final
    : public OpConversionPattern<sim::SimRefStoreOp> {
public:
  RefStoreConversion(
      const TypeConverter &converter, MLIRContext *context,
      uint64_t stateBitCount, const NativeStateLayout *directLayout,
      bool experimentalTwoState,
      const DenseMap<Operation *, NativeStateAccessInfo> &stateAccesses,
      const LocalStorageLowering *, const NativeStateLayout *)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        directLayout(directLayout), experimentalTwoState(experimentalTwoState),
        stateAccesses(stateAccesses) {
    setHasBoundedRewriteRecursion();
  }

  LogicalResult
  matchAndRewrite(sim::SimRefStoreOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getReference().size() != 1 || adaptor.getValue().empty())
      return failure();
    Type valueType = op.getValue().getType();
    // A known store leaves the destination's zero unknown bits in place.
    bool twoState =
        useTwoStateSpecialization(op, experimentalTwoState) ||
        ::talos::schedule::has<::talos::schedule::Field::NativeKnownStore>(op);
    auto proof = stateAccesses.find(op);
    const NativeStateAccessInfo *access =
        proof == stateAccesses.end() ? nullptr : &proof->second;
    std::optional<unsigned> width = nativeStateWidth(valueType);
    if (!width)
      return failure();
    IntegerType plane = rewriter.getIntegerType(*width);
    bool assumeClean =
        ::talos::schedule::has<assumeCleanSpecializationAttr>(op);
    // A clocked kernel's direct store: its wakes wait in the held set until
    // the updates of its NBA region are complete.
    bool nbaEquivalent = ::talos::schedule::has<
        ::talos::schedule::Field::EvalNbaEquivalentStore>(op);
    sim::SimFuncOp function = op->getParentOfType<sim::SimFuncOp>();
    sim::EntryKind entryKind = function.getEntryKind();
    bool runtimePublication =
        native::has<native::RuntimePublicationCertified>(function);
    bool continuous = !isa<sim::EventType>(valueType) &&
                      (sim::has<sim::metadata::ContinuousStore>(op) ||
                       entryKind == sim::EntryKind::Continuous ||
                       entryKind == sim::EntryKind::PortInput ||
                       entryKind == sim::EntryKind::PortOutput);
    std::optional<DirectStaticStateRange> directRange =
        resolveDirectStaticStateRange(adaptor.getReference().front(), *width,
                                      directLayout);
    // Guard the entire procedural store, including its publication. The clean
    // path can use exact static fanout without canonical reloads; a live writer
    // or observer invalidates the global flag before entering the slow path.
    // Continuous assignments must retain their contribution for a later
    // force/release (IEEE 1800-2023 10.6.2), even when currently unforced.
    bool directContinuous =
        continuous && directLayout && directLayout->directContinuous;
    if (directRange && directRange->guarded && !assumeClean &&
        (!continuous || directContinuous) && !runtimePublication &&
        !native::has<native::GuardedRefStore>(op)) {
      Block *head = rewriter.getInsertionBlock();
      Block *tail = rewriter.splitBlock(head, op->getIterator());
      Region *region = head->getParent();
      Block *fast = rewriter.createBlock(region, tail->getIterator());
      Block *slow = rewriter.createBlock(region, tail->getIterator());
      for (auto [block, clean] :
           {std::pair{fast, true}, std::pair{slow, false}}) {
        rewriter.setInsertionPointToEnd(block);
        Operation *clone = rewriter.clone(*op);
        native::mark<native::GuardedRefStore>(clone);
        if (clean)
          ::talos::schedule::set<assumeCleanSpecializationAttr>(
              clone, rewriter.getUnitAttr());
        cf::BranchOp::create(rewriter, op.getLoc(), tail);
      }
      rewriter.setInsertionPointToEnd(head);
      Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
      Value address =
          LLVM::AddressOfOp::create(rewriter, op.getLoc(), pointer,
                                    "__talos_state_specialization_fast_v1");
      Value flag = LLVM::LoadOp::create(rewriter, op.getLoc(),
                                        rewriter.getI32Type(), address, 4);
      Value allowed = arith::CmpIOp::create(
          rewriter, op.getLoc(), arith::CmpIPredicate::ne, flag,
          llvmConstant(rewriter, op.getLoc(), rewriter.getI32Type(), 0));
      markLikelyTrue(
          cf::CondBranchOp::create(rewriter, op.getLoc(), allowed, fast, slow));
      rewriter.eraseOp(op);
      return success();
    }
    bool needsNotification = true;
    // Exact fanout proves that an absent root has no language-level waiter.
    // Direct roots are also immune to external writes (VPI-off/read), while a
    // guarded VPI-full root may elide observers only in its clean fast body.
    if (directLayout && directLayout->transitionHandlesExact)
      if (directRange && (assumeClean || !directRange->guarded))
        needsNotification =
            directLayout->transitionHandles.contains(directRange->staticID);
    if (needsNotification && directRange &&
        (assumeClean || !directRange->guarded))
      if (auto roots = native::get<native::NoTransitionRoots>(function))
        needsNotification = !llvm::is_contained(
            roots.asArrayRef(), static_cast<int32_t>(directRange->staticID));
    if (isa<LLVM::LLVMPointerType>(adaptor.getValue().front().getType())) {
      Location location = op.getLoc();
      Value handle = adaptor.getReference().front();
      bool fourState = containsLogic(valueType) && !twoState;
      auto snapshot = [&](schedule::StatePlane plane, bool unknown) {
        return loadBulkStatePlane(rewriter, location, handle, *width, plane,
                                  unknown, stateBitCount, directLayout,
                                  assumeClean);
      };
      Value oldValue, oldUnknown;
      if (needsNotification) {
        oldValue = snapshot(schedule::StatePlane::Value, false);
        if (fourState)
          oldUnknown = snapshot(schedule::StatePlane::Unknown, true);
      }
      auto store = [&](Value input, schedule::StatePlane plane) {
        if (tryStoreBulkDirect(rewriter, location, handle, input, *width, plane,
                               directLayout, assumeClean, continuous))
          return true;
        Value changed =
            entryAlloca(rewriter, location, rewriter.getI8Type(), 1, 1);
        storeBulkStatePlane(rewriter, location, handle, input, *width, plane,
                            stateBitCount, changed, continuous);
        return false;
      };
      Value newValue = adaptor.getValue().front();
      bool direct = store(newValue, schedule::StatePlane::Value);
      Value newUnknown;
      if (fourState) {
        newUnknown = adaptor.getValue()[1];
        direct &= store(newUnknown, schedule::StatePlane::Unknown);
      }
      if (needsNotification) {
        // Runtime stores may be partially suppressed by an override. Publish
        // the actual visible value, with the same semantics as scalar stores.
        if (!direct) {
          newValue = snapshot(schedule::StatePlane::Value, false);
          if (fourState)
            newUnknown = snapshot(schedule::StatePlane::Unknown, true);
        }
        notifyBulkSignal(
            rewriter, location, handle, *width, oldValue, oldUnknown, newValue,
            newUnknown,
            ::talos::schedule::get<schedule::metadata::evalSourceOwner>(op),
            nbaEquivalent);
      }
      rewriter.eraseOp(op);
      return success();
    }
    Value guardedPermission;
    if (directRange && directRange->guarded && !assumeClean)
      guardedPermission = staticSpecializationGuard(
          rewriter, op.getLoc(), directRange->staticID,
          TALOS_RT_STATIC_ROOT_READ | TALOS_RT_STATIC_ROOT_WRITE);
    Value storedValue = adaptor.getValue().front();
    if (isa<FloatType>(valueType))
      storedValue =
          arith::BitcastOp::create(rewriter, op.getLoc(), plane, storedValue);
    // A ranked process keeps its original frame across the compiler-selected
    // Active handoff. Publish its packed blocking write as one transaction.
    // The runtime owns the actual armed waits, the retained driver value and
    // any externally masked bits (1800-2023 4.6, 9.4.2, 10.6.2).
    auto sourceOwner = schedule::get<schedule::metadata::evalSourceOwner>(op);
    bool ownSource =
        !sourceOwner ||
        (sourceOwner.getCodeUnit() && function.getCodeUnitId() &&
         sourceOwner.getCodeUnit().getUInt() == *function.getCodeUnitId());
    if (native::has<native::RankedSignalWriter>(function) &&
        function.getEntryKind() != sim::EntryKind::Function && ownSource &&
        !nbaEquivalent && needsNotification &&
        (!directRange || directRange->guarded) &&
        schedule::has<schedule::Field::EvalRuntimeCalendar>(
            op->getParentOfType<ModuleOp>()) &&
        *width <= 64 && storedValue.getType() == plane &&
        sim::getPackedScalarType(valueType)) {
      auto loc = op.getLoc();
      auto i64 = rewriter.getI64Type(), i32 = rewriter.getI32Type();
      auto word = [&](Value bits) -> Value {
        return bits.getType() == i64
                   ? bits
                   : arith::ExtUIOp::create(rewriter, loc, i64, bits)
                         .getResult();
      };
      bool fourState = containsLogic(valueType) && !twoState;
      Value valuePlane = detail::createStatePlaneAddress(
          rewriter, loc, schedule::StatePlane::Value);
      Value unknownPlane =
          fourState ? detail::createStatePlaneAddress(
                          rewriter, loc, schedule::StatePlane::Unknown)
                    : LLVM::ZeroOp::create(rewriter, loc, valuePlane.getType())
                          .getResult();
      uint32_t flags = (continuous ? TALOS_RT_FRAME_STORE_CONTINUOUS : 0) |
                       (fourState ? TALOS_RT_FRAME_STORE_UNKNOWN : 0);
      Value unknown = fourState && adaptor.getValue().size() == 2
                          ? word(adaptor.getValue()[1])
                          : llvmConstant(rewriter, loc, i64, 0);
      LLVM::CallOp::create(
          rewriter, loc, TypeRange{}, "talos_rt_v1_native_frame_store",
          ValueRange{loadCurrentRuntimeContext(rewriter, loc), valuePlane,
                     unknownPlane,
                     llvmConstant(rewriter, loc, i64, stateBitCount),
                     adaptor.getReference().front(),
                     llvmConstant(rewriter, loc, i32, *width),
                     llvmConstant(rewriter, loc, i32, flags), word(storedValue),
                     unknown});
      rewriter.eraseOp(op);
      return success();
    }
    if (!directRange && !runtimePublication &&
        (isa_and_nonnull<IntegerType>(sim::getPackedScalarType(valueType)) ||
         containsLogic(valueType)) &&
        emitDirectDynamicPackedStore(
            rewriter, op.getLoc(), adaptor.getReference().front(), storedValue,
            adaptor.getValue().size() == 2 ? adaptor.getValue()[1] : Value{},
            directLayout, assumeClean, continuous, twoState,
            ::talos::schedule::get<schedule::metadata::evalSourceOwner>(op),
            access, nbaEquivalent)) {
      rewriter.eraseOp(op);
      return success();
    }
    if (!needsNotification) {
      (void)storeStatePlane(
          rewriter, op.getLoc(), adaptor.getReference().front(), storedValue,
          schedule::StatePlane::Value, stateBitCount, directLayout,
          guardedPermission, assumeClean, /*trackChange=*/false, continuous);
      if (containsLogic(valueType) && !twoState)
        (void)storeStatePlane(
            rewriter, op.getLoc(), adaptor.getReference().front(),
            adaptor.getValue().size() == 2
                ? adaptor.getValue()[1]
                : llvmConstant(rewriter, op.getLoc(), plane, 0),
            schedule::StatePlane::Unknown, stateBitCount, directLayout,
            guardedPermission, assumeClean,
            /*trackChange=*/false, continuous);
      rewriter.eraseOp(op);
      return success();
    }
    Value oldValue =
        loadStatePlane(rewriter, op.getLoc(), adaptor.getReference().front(),
                       plane, schedule::StatePlane::Value, false, stateBitCount,
                       directLayout, guardedPermission, assumeClean, access);
    Value oldUnknown;
    if (containsLogic(valueType))
      oldUnknown = twoState
                       ? llvmConstant(rewriter, op.getLoc(), plane, 0)
                       : loadStatePlane(rewriter, op.getLoc(),
                                        adaptor.getReference().front(), plane,
                                        schedule::StatePlane::Unknown, true,
                                        stateBitCount, directLayout,
                                        guardedPermission, assumeClean, access);
    Value notificationValue = storedValue;
    Value notificationUnknown = adaptor.getValue().size() == 2 && !twoState
                                    ? adaptor.getValue()[1]
                                    : Value{};
    if (isa<sim::StringType>(valueType)) {
      Value comparison =
          LLVM::CallOp::create(rewriter, op.getLoc(),
                               TypeRange{rewriter.getI32Type()},
                               SymbolRefAttr::get(rewriter.getContext(),
                                                  "talos_rt_v1_string_compare"),
                               ValueRange{oldValue, storedValue})
              .getResult();
      Value equal = arith::CmpIOp::create(
          rewriter, op.getLoc(), arith::CmpIPredicate::eq, comparison,
          llvmConstant(rewriter, op.getLoc(), rewriter.getI32Type(), 0));
      notificationValue = arith::SelectOp::create(rewriter, op.getLoc(), equal,
                                                  oldValue, storedValue);
    }
    // Change-first store: a clean direct scalar root with an inline
    // transition tests old against new once, and stores both planes,
    // publishes and wakes only on a change. Its canonical-proof publication
    // then also runs only on the changed path.
    // IEEE 1800-2023 4.3: only a change in state of a variable is an update
    // event, and any algorithm with the reference algorithm's user-visible
    // effect is allowed. Writing the value already held changes no state, so
    // skipping it leaves memory identical and wakes nothing (9.4.2: implicit
    // events are value changes; x->x and z->z are no edge). The state is
    // 4-valued (6.3.1), so the test compares both planes: 0<->x and x<->z
    // changes still store and reach the transition, which applies the edge
    // rules of Table 9-2. VPI value-change callbacks also fire only on a
    // change (38.36.1), and direct roots are VPI-off or read-only.
    bool inlineTransition = !runtimePublication && directRange &&
                            (assumeClean || !directRange->guarded) &&
                            directLayout &&
                            directLayout->transitionHandlesExact;
    // Non-continuous clean direct stores publish the stored value itself: no
    // override can mask it, so no visible reload is needed (see below).
    if (inlineTransition && !continuous && *width <= 64 &&
        !isa<sim::StringType, FloatType, sim::EventType>(valueType)) {
      Value storedUnknown;
      if (containsLogic(valueType) && !twoState)
        storedUnknown = adaptor.getValue().size() == 2
                            ? adaptor.getValue()[1]
                            : llvmConstant(rewriter, op.getLoc(), plane, 0);
      Value reference = adaptor.getReference().front();
      notifySignal(
          rewriter, op.getLoc(), reference, *width, oldValue, oldUnknown,
          storedValue, storedUnknown, directRange,
          ::talos::schedule::get<schedule::metadata::evalSourceOwner>(op),
          nbaEquivalent, [&] {
            (void)storeStatePlane(rewriter, op.getLoc(), reference, storedValue,
                                  schedule::StatePlane::Value, stateBitCount,
                                  directLayout, Value{}, assumeClean,
                                  /*trackChange=*/false,
                                  /*continuous=*/false);
            if (storedUnknown)
              (void)storeStatePlane(
                  rewriter, op.getLoc(), reference, storedUnknown,
                  schedule::StatePlane::Unknown, stateBitCount, directLayout,
                  Value{}, assumeClean, /*trackChange=*/false,
                  /*continuous=*/false);
          });
      rewriter.eraseOp(op);
      return success();
    }
    Value valueChanged =
        storeStatePlane(rewriter, op.getLoc(), adaptor.getReference().front(),
                        storedValue, schedule::StatePlane::Value, stateBitCount,
                        directLayout, guardedPermission, assumeClean,
                        /*trackChange=*/true, continuous);
    // Runtime plane stores can suppress a write while force or procedural
    // assign owns the variable. Publish the value that actually became
    // visible, not the attempted procedural assignment (IEEE 1800-2017
    // 10.6.1-10.6.2). A no-change store likewise retains the already loaded
    // value, so the same selects cover both cases without another plane load.
    notificationValue = arith::SelectOp::create(
        rewriter, op.getLoc(), valueChanged, notificationValue, oldValue);
    if (containsLogic(valueType) && !twoState) {
      Value storedUnknown = adaptor.getValue().size() == 2
                                ? adaptor.getValue()[1]
                                : llvmConstant(rewriter, op.getLoc(), plane, 0);
      Value unknownChanged = storeStatePlane(
          rewriter, op.getLoc(), adaptor.getReference().front(), storedUnknown,
          schedule::StatePlane::Unknown, stateBitCount, directLayout,
          guardedPermission, assumeClean,
          /*trackChange=*/true, continuous);
      notificationUnknown = arith::SelectOp::create(
          rewriter, op.getLoc(), unknownChanged, storedUnknown, oldUnknown);
    }
    // A generic packed store can update only the currently unmasked bits.
    // Reload its canonical result so partial external forces cannot leak the
    // attempted value through transition publication. Direct clean stores
    // have no override mask and keep the select-only fast path above.
    bool needsVisibleReload =
        sim::getPackedWidth(valueType).has_value() &&
        ((continuous &&
          !(directContinuous &&
            (assumeClean || (directRange && !directRange->guarded)))) ||
         !directLayout || !directRange ||
         (directRange->guarded && !assumeClean));
    if (needsVisibleReload) {
      notificationValue = loadStatePlane(
          rewriter, op.getLoc(), adaptor.getReference().front(), plane,
          schedule::StatePlane::Value, false, stateBitCount, directLayout,
          guardedPermission, assumeClean, access);
      if (containsLogic(valueType))
        notificationUnknown =
            twoState ? llvmConstant(rewriter, op.getLoc(), plane, 0)
                     : loadStatePlane(rewriter, op.getLoc(),
                                      adaptor.getReference().front(), plane,
                                      schedule::StatePlane::Unknown, true,
                                      stateBitCount, directLayout,
                                      guardedPermission, assumeClean, access);
    }
    if (isa<FloatType>(valueType)) {
      Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
      auto save = [&](Value value) {
        Value storage =
            entryAlloca(rewriter, op.getLoc(), value.getType(), 1, 1);
        LLVM::StoreOp::create(rewriter, op.getLoc(), value, storage, 1);
        return storage;
      };
      Value contextAddress = LLVM::AddressOfOp::create(
          rewriter, op.getLoc(), pointer, "__talos_current_context");
      Value runtimeContext = LLVM::LoadOp::create(rewriter, op.getLoc(),
                                                  pointer, contextAddress, 8);
      LLVM::CallOp::create(
          rewriter, op.getLoc(), TypeRange{},
          SymbolRefAttr::get(rewriter.getContext(),
                             "talos_rt_v1_scheduler_real_transition"),
          ValueRange{runtimeContext, adaptor.getReference().front(),
                     llvmConstant(rewriter, op.getLoc(), rewriter.getI32Type(),
                                  *width),
                     save(oldValue), save(notificationValue)});
    } else {
      // IEEE 1800-2017 Clause 31.9.1 transport commits must wake the
      // runtime-owned delayed-terminal coordinator. Select the generic
      // publication call while lowering this structurally certified cold
      // function; ordinary stores retain the branch-free static AOT call.
      notifySignal(
          rewriter, op.getLoc(), adaptor.getReference().front(), *width,
          oldValue, oldUnknown, notificationValue, notificationUnknown,
          inlineTransition ? directRange : std::nullopt,
          ::talos::schedule::get<schedule::metadata::evalSourceOwner>(op),
          nbaEquivalent);
    }
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
  const DenseMap<Operation *, NativeStateAccessInfo> &stateAccesses;
};

class NetReadConversion final : public OpConversionPattern<sim::SimNetReadOp> {
public:
  NetReadConversion(const TypeConverter &converter, MLIRContext *context,
                    uint64_t stateBitCount,
                    const NativeStateLayout *directLayout,
                    bool experimentalTwoState)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        directLayout(directLayout), experimentalTwoState(experimentalTwoState) {
  }

  LogicalResult
  matchAndRewrite(sim::SimNetReadOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type resultType = op.getResult().getType();
    bool twoState = readsKnownLocation(op, experimentalTwoState);
    std::optional<unsigned> width = nativeStateWidth(resultType);
    if (!width || adaptor.getNet().size() != 1)
      return failure();
    IntegerType plane = rewriter.getIntegerType(*width);
    Value value = loadStatePlane(
        rewriter, op.getLoc(), adaptor.getNet().front(), plane,
        schedule::StatePlane::Value, false, stateBitCount, directLayout);
    value = maskStoragePlane(rewriter, op.getLoc(), value, resultType, false);
    if (isa<FloatType>(resultType))
      value =
          arith::BitcastOp::create(rewriter, op.getLoc(), resultType, value);
    SmallVector<Value> converted{value};
    if (containsLogic(resultType)) {
      Value unknown =
          twoState
              ? llvmConstant(rewriter, op.getLoc(), plane, 0)
              : loadStatePlane(rewriter, op.getLoc(), adaptor.getNet().front(),
                               plane, schedule::StatePlane::Unknown, true,
                               stateBitCount, directLayout);
      converted.push_back(
          maskStoragePlane(rewriter, op.getLoc(), unknown, resultType, true));
    }
    SmallVector<ValueRange> replacements{ValueRange(converted)};
    rewriter.replaceOpWithMultiple(op, replacements);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
};

class DriverReadConversion final
    : public OpConversionPattern<sim::SimDriverReadOp> {
public:
  DriverReadConversion(const TypeConverter &converter, MLIRContext *context,
                       uint64_t stateBitCount,
                       const NativeStateLayout *directLayout,
                       bool experimentalTwoState)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        directLayout(directLayout), experimentalTwoState(experimentalTwoState) {
  }

  LogicalResult
  matchAndRewrite(sim::SimDriverReadOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type resultType = op.getResult().getType();
    bool twoState = useTwoStateSpecialization(op, experimentalTwoState);
    std::optional<unsigned> width = nativeStateWidth(resultType);
    if (!width || adaptor.getDriver().size() != 1)
      return failure();
    IntegerType plane = rewriter.getIntegerType(*width);
    Value value = loadStatePlane(
        rewriter, op.getLoc(), adaptor.getDriver().front(), plane,
        schedule::StatePlane::Value, false, stateBitCount, directLayout);
    value = maskStoragePlane(rewriter, op.getLoc(), value, resultType, false);
    if (isa<FloatType>(resultType))
      value =
          arith::BitcastOp::create(rewriter, op.getLoc(), resultType, value);
    SmallVector<Value> converted{value};
    if (containsLogic(resultType)) {
      Value unknown = twoState
                          ? llvmConstant(rewriter, op.getLoc(), plane, 0)
                          : loadStatePlane(rewriter, op.getLoc(),
                                           adaptor.getDriver().front(), plane,
                                           schedule::StatePlane::Unknown, true,
                                           stateBitCount, directLayout);
      converted.push_back(
          maskStoragePlane(rewriter, op.getLoc(), unknown, resultType, true));
    }
    SmallVector<ValueRange> replacements{ValueRange(converted)};
    rewriter.replaceOpWithMultiple(op, replacements);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
};

class NetWriteConversion final
    : public OpConversionPattern<sim::SimNetWriteOp> {
public:
  NetWriteConversion(const TypeConverter &converter, MLIRContext *context,
                     uint64_t stateBitCount,
                     const NativeStateLayout *directLayout,
                     bool experimentalTwoState)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        directLayout(directLayout), experimentalTwoState(experimentalTwoState) {
  }

  LogicalResult
  matchAndRewrite(sim::SimNetWriteOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type valueType = op.getValue().getType();
    bool twoState = useTwoStateSpecialization(op, experimentalTwoState);
    std::optional<unsigned> width = nativeStateWidth(valueType);
    if (!width || adaptor.getNet().size() != 1 || adaptor.getValue().empty())
      return failure();
    IntegerType plane = rewriter.getIntegerType(*width);
    Value handle = adaptor.getNet().front();
    Value oldValue = loadStatePlane(rewriter, op.getLoc(), handle, plane,
                                    schedule::StatePlane::Value, false,
                                    stateBitCount, directLayout);
    Value oldUnknown;
    if (containsLogic(valueType))
      oldUnknown = twoState
                       ? llvmConstant(rewriter, op.getLoc(), plane, 0)
                       : loadStatePlane(rewriter, op.getLoc(), handle, plane,
                                        schedule::StatePlane::Unknown, true,
                                        stateBitCount, directLayout);
    Value newValue = adaptor.getValue().front();
    if (isa<FloatType>(valueType))
      newValue =
          arith::BitcastOp::create(rewriter, op.getLoc(), plane, newValue);
    Value newUnknown = adaptor.getValue().size() == 2 && !twoState
                           ? adaptor.getValue()[1]
                           : Value{};
    (void)storeStatePlane(rewriter, op.getLoc(), handle, newValue,
                          schedule::StatePlane::Value, stateBitCount,
                          directLayout);
    if (containsLogic(valueType) && !twoState)
      (void)storeStatePlane(rewriter, op.getLoc(), handle, newUnknown,
                            schedule::StatePlane::Unknown, stateBitCount,
                            directLayout);

    if (isa<FloatType>(valueType)) {
      Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
      auto save = [&](Value value) {
        Value storage =
            entryAlloca(rewriter, op.getLoc(), value.getType(), 1, 1);
        LLVM::StoreOp::create(rewriter, op.getLoc(), value, storage, 1);
        return storage;
      };
      Value contextAddress = LLVM::AddressOfOp::create(
          rewriter, op.getLoc(), pointer, "__talos_current_context");
      Value runtimeContext = LLVM::LoadOp::create(rewriter, op.getLoc(),
                                                  pointer, contextAddress, 8);
      LLVM::CallOp::create(
          rewriter, op.getLoc(), TypeRange{},
          SymbolRefAttr::get(rewriter.getContext(),
                             "talos_rt_v1_scheduler_real_transition"),
          ValueRange{runtimeContext, handle,
                     llvmConstant(rewriter, op.getLoc(), rewriter.getI32Type(),
                                  *width),
                     save(oldValue), save(newValue)});
    } else {
      notifySignal(
          rewriter, op.getLoc(), handle, *width, oldValue, oldUnknown, newValue,
          containsLogic(valueType) ? newUnknown : Value{},
          resolveDirectStaticStateRange(handle, *width, directLayout),
          ::talos::schedule::get<schedule::metadata::evalSourceOwner>(op));
    }
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStateLayout *directLayout;
  bool experimentalTwoState;
};

class NetCountDriversConversion final
    : public OpConversionPattern<sim::SimNetCountDriversOp> {
public:
  using OpConversionPattern::OpConversionPattern;

  LogicalResult
  matchAndRewrite(sim::SimNetCountDriversOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getNet().size() != 1)
      return failure();
    Location location = op.getLoc();
    Type i32 = rewriter.getI32Type();
    Value context = loadCurrentRuntimeContext(rewriter, location);
    SmallVector<Value, 5> outputs;
    outputs.reserve(5);
    for (unsigned index = 0; index != 5; ++index) {
      Value output = entryAlloca(rewriter, location, i32, 1, 4);
      LLVM::StoreOp::create(rewriter, location,
                            llvmConstant(rewriter, location, i32, 0), output,
                            4);
      outputs.push_back(output);
    }
    SmallVector<Value, 7> arguments{context, adaptor.getNet().front()};
    llvm::append_range(arguments, outputs);
    Value status = LLVM::CallOp::create(
                       rewriter, location, TypeRange{i32},
                       SymbolRefAttr::get(rewriter.getContext(),
                                          "talos_rt_v1_net_count_drivers"),
                       arguments)
                       .getResult();
    reportRuntimeControlStatus(rewriter, location, context, status);
    SmallVector<Value, 5> replacements;
    for (Value output : outputs)
      replacements.push_back(
          LLVM::LoadOp::create(rewriter, location, i32, output, 4));
    rewriter.replaceOp(op, replacements);
    return success();
  }
};

class PassSwitchControlConversion final
    : public OpConversionPattern<sim::SimPassSwitchControlOp> {
public:
  using OpConversionPattern::OpConversionPattern;

  LogicalResult
  matchAndRewrite(sim::SimPassSwitchControlOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getControl().empty() || adaptor.getControl().size() > 2 ||
        op.getPassSwitchId() >= UINT32_MAX)
      return failure();
    Location location = op.getLoc();
    Type i32 = rewriter.getI32Type();
    Value context = loadCurrentRuntimeContext(rewriter, location);
    auto extend = [&](Value value) -> Value {
      return LLVM::ZExtOp::create(rewriter, location, i32, value);
    };
    Value unknown = adaptor.getControl().size() == 2
                        ? extend(adaptor.getControl()[1])
                        : llvmConstant(rewriter, location, i32, 0);
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_pass_switch_control"),
            ValueRange{
                context,
                llvmConstant(rewriter, location, i32, op.getPassSwitchId()),
                extend(adaptor.getControl().front()), unknown})
            .getResult();
    reportRuntimeControlStatus(rewriter, location, context, status);
    rewriter.eraseOp(op);
    return success();
  }
};

class PassSwitchControlDelayedConversion final
    : public OpConversionPattern<sim::SimPassSwitchControlDelayedOp> {
public:
  using OpConversionPattern::OpConversionPattern;

  LogicalResult
  matchAndRewrite(sim::SimPassSwitchControlDelayedOp op,
                  OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getControl().empty() || adaptor.getTurnOnDelay().size() != 1 ||
        adaptor.getTurnOffDelay().size() != 1 ||
        adaptor.getUnknownDelay().size() != 1 ||
        op.getPassSwitchId() >= UINT32_MAX)
      return failure();
    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value context =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto extend = [&](Value value) -> Value {
      return LLVM::ZExtOp::create(rewriter, location, i32, value);
    };
    Value unknown = adaptor.getControl().size() == 2
                        ? extend(adaptor.getControl()[1])
                        : llvmConstant(rewriter, location, i32, 0);
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_pass_switch_control_delayed"),
            ValueRange{
                context,
                llvmConstant(rewriter, location, i32, op.getPassSwitchId()),
                extend(adaptor.getControl().front()), unknown,
                adaptor.getTurnOnDelay().front(),
                adaptor.getTurnOffDelay().front(),
                adaptor.getUnknownDelay().front()})
            .getResult();
    reportRuntimeControlStatus(rewriter, location, context, status);
    rewriter.eraseOp(op);
    return success();
  }
};

class MosDriveDelayedConversion final
    : public OpConversionPattern<sim::SimMosDriveDelayedOp> {
public:
  using OpConversionPattern::OpConversionPattern;

  LogicalResult
  matchAndRewrite(sim::SimMosDriveDelayedOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getControl().empty() || adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1 ||
        op.getPassSwitchId() >= UINT32_MAX)
      return failure();
    Location location = op.getLoc();
    Type i32 = rewriter.getI32Type();
    Value context = loadCurrentRuntimeContext(rewriter, location);
    auto extend = [&](Value value) -> Value {
      return LLVM::ZExtOp::create(rewriter, location, i32, value);
    };
    Value unknown = adaptor.getControl().size() == 2
                        ? extend(adaptor.getControl()[1])
                        : llvmConstant(rewriter, location, i32, 0);
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_mos_drive_delayed"),
            ValueRange{
                context,
                llvmConstant(rewriter, location, i32, op.getPassSwitchId()),
                extend(adaptor.getControl().front()), unknown,
                adaptor.getRiseDelay().front(), adaptor.getFallDelay().front(),
                adaptor.getTurnoffDelay().front()})
            .getResult();
    reportRuntimeControlStatus(rewriter, location, context, status);
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

void populateKnownRootsToLLVMConversionPatterns(
    RewritePatternSet &patterns, TypeConverter &converter,
    const NativeStateLayout &layout) {
  patterns.add<KnownRootsConversion, KnownRootsBranchConversion>(
      converter, patterns.getContext(), layout);
}

void populateStateReadWriteToLLVMConversionPatterns(
    RewritePatternSet &patterns, TypeConverter &converter,
    uint64_t stateBitCount, const NativeStateLayout *directLayout,
    bool experimentalTwoState,
    const DenseMap<Operation *, NativeStateAccessInfo> &stateAccesses,
    const LocalStorageLowering *locals, const NativeStateLayout *layout) {
  patterns.add<KnownValueConversion>(converter, patterns.getContext());
  patterns.add<BulkRefCopyConversion>(converter, patterns.getContext(),
                                      stateBitCount, directLayout,
                                      experimentalTwoState);
  patterns.add<RefLoadConversion, RefStoreConversion>(
      converter, patterns.getContext(), stateBitCount, directLayout,
      experimentalTwoState, stateAccesses, locals, layout);
  patterns.add<NetReadConversion, DriverReadConversion, NetWriteConversion>(
      converter, patterns.getContext(), stateBitCount, directLayout,
      experimentalTwoState);
  patterns.add<NetCountDriversConversion>(converter, patterns.getContext());
  patterns.add<PassSwitchControlConversion, PassSwitchControlDelayedConversion,
               MosDriveDelayedConversion>(converter, patterns.getContext());
}

} // namespace talos::detail
