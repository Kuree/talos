//===- SimulationStatePlaneLowering.cpp - Native state planes --------===//

#include "NativeHandleChain.h"
#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"

#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MathExtras.h"

using namespace mlir;

namespace talos {

namespace detail {

void notifySignal(ConversionPatternRewriter &builder, Location location,
                  Value handle, uint64_t width, Value oldValue,
                  Value oldUnknown, Value newValue, Value newUnknown,
                  std::optional<DirectStaticStateRange> directRange,
                  schedule::SourceOwnerAttr sourceOwner, bool nbaEquivalent,
                  llvm::function_ref<void()> storeOnChange) {
  Type pointer = LLVM::LLVMPointerType::get(builder.getContext());
  Type i64 = builder.getI64Type();
  Value address = LLVM::AddressOfOp::create(builder, location, pointer,
                                            "__talos_current_context");
  Value context = LLVM::LoadOp::create(builder, location, pointer, address, 8);
  if (directRange && width <= 64) {
    auto scalar = [&](Value value) -> Value {
      if (!value)
        return llvmConstant(builder, location, i64, uint64_t{0});
      if (value.getType() == i64)
        return value;
      return LLVM::ZExtOp::create(builder, location, i64, value);
    };
    Value oldValueScalar = scalar(oldValue);
    Value oldUnknownScalar = scalar(oldUnknown);
    Value newValueScalar = scalar(newValue);
    Value newUnknownScalar = scalar(newUnknown);
    Value changed = arith::OrIOp::create(
        builder, location,
        arith::XOrIOp::create(builder, location, oldValueScalar,
                              newValueScalar),
        arith::XOrIOp::create(builder, location, oldUnknownScalar,
                              newUnknownScalar));
    Value unchanged = arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::eq, changed,
        llvmConstant(builder, location, i64, uint64_t{0}));
    Block *head = builder.getInsertionBlock();
    Block *continuation = builder.splitBlock(head, builder.getInsertionPoint());
    Region *region = head->getParent();
    Block *publish = builder.createBlock(region, continuation->getIterator());
    builder.setInsertionPointToEnd(head);
    cf::CondBranchOp::create(builder, location, unchanged, continuation,
                             ValueRange{}, publish, ValueRange{});
    builder.setInsertionPointToEnd(publish);
    // A change-first store writes the planes only on this path. Unchanged,
    // the old planes already hold the result and there is no update event
    // (IEEE 1800-2023 4.3); the test covers both planes (6.3.1).
    if (storeOnChange)
      storeOnChange();
    auto transition = schedule::NativeTransitionOp::create(
        builder, location, context,
        llvmConstant(builder, location, i64, directRange->localOffset),
        oldValueScalar, oldUnknownScalar, newValueScalar, newUnknownScalar,
        builder.getI64IntegerAttr(directRange->staticID),
        builder.getI64IntegerAttr(width), sourceOwner);
    if (nbaEquivalent)
      ::talos::schedule::set<::talos::schedule::Field::EvalNbaEquivalentStore>(
          transition, builder.getUnitAttr());
    cf::BranchOp::create(builder, location, continuation);
    builder.setInsertionPointToStart(continuation);
    return;
  }
  // Without an inline change test the store stays unconditional, in source
  // order before the runtime transition.
  if (storeOnChange)
    storeOnChange();
  // The op takes its width from the planes, whose types its verifier keeps
  // equal; a plane of another width would publish other bits than the store
  // wrote. Fail closed in every build. Every caller sizes the planes by
  // `width`, so no input IR reaches this.
  if (oldValue.getType().getIntOrFloatBitWidth() != width)
    llvm::report_fatal_error(
        "native transition planes are " +
        llvm::Twine(oldValue.getType().getIntOrFloatBitWidth()) +
        " bits wide, but their store writes " + llvm::Twine(width) + " bits");
  schedule::NativeHandleTransitionOp::create(
      builder, location, context, handle, oldValue, oldUnknown, newValue,
      newUnknown, sourceOwner, nbaEquivalent);
}
std::optional<DirectStaticStateRange>
resolveDirectStaticStateRange(Value handle, unsigned width,
                              const NativeStateLayout *layout) {
  if (!layout || width == 0)
    return std::nullopt;
  std::optional<uint64_t> value = resolveCFGConstantInteger(handle);
  if (!value)
    return std::nullopt;
  talos_rt_stable_handle_v1 decoded{};
  if (!talos_rt_stable_handle_decode(*value, &decoded) ||
      decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset < 0)
    return std::nullopt;
  bool direct = layout->directHandles.contains(decoded.id);
  bool guarded = layout->guardedHandles.contains(decoded.id);
  if (!direct && !guarded)
    return std::nullopt;
  const auto *bound = layout->findBound(decoded.id);
  // Direct accesses are authorized either by the specialization policy or by
  // a fully static VPI-off wide-NBA plan, which records its roots in the same
  // direct-handle inventory before conversion.
  if (!bound || static_cast<uint64_t>(decoded.offset) > bound->width ||
      width > bound->width - static_cast<uint64_t>(decoded.offset))
    return std::nullopt;
  return DirectStaticStateRange{
      bound->offset + static_cast<uint64_t>(decoded.offset),
      static_cast<uint64_t>(decoded.offset),
      decoded.id,
      guarded,
      decoded.offset == 0 && width == bound->width ? bound->containerWidth : 0,
      layout->packedStorage
          ? layout->packedStorage->get(bound->type, bound->offset,
                                       decoded.offset, width)
          : std::nullopt};
}

/// A packed span of a state plane: the bytes from `byteOffset` that hold a
/// root's bits from `bitOffset`, read as `span` when it was read.
struct DirectPackedPlane {
  schedule::StatePlane plane;
  uint64_t byteOffset;
  IntegerType spanType;
  Value span;
  unsigned bitOffset;

  /// Write the span.
  void store(OpBuilder &builder, Location location, Value value) const {
    schedule::NativeStateStoreOp::create(builder, location, value, plane,
                                         Value{}, byteOffset, 1);
  }
};

DirectPackedPlane loadDirectPackedPlane(
    OpBuilder &builder, Location location, schedule::StatePlane statePlane,
    uint64_t bitOffset, unsigned width, unsigned containerWidth = 0,
    bool read = true, std::optional<PackedAccessUnit> unit = {});
Value extractDirectPackedPlane(OpBuilder &builder, Location location,
                               const DirectPackedPlane &plane,
                               IntegerType resultType);

struct DirectDynamicStateRange {
  Value valid;
  Value bitOffset;
  uint64_t rootOffset;
  uint64_t localOffset;
  uint64_t rootWidth;
  uint32_t staticID;
  bool guarded;
  bool inBounds;
  bool wholeOrInvalid;
  unsigned containerWidth;
};

std::optional<DirectDynamicStateRange>
resolveDirectDynamicStateRange(Value handle, unsigned width,
                               const NativeStateLayout *layout,
                               const NativeStateAccessInfo *access) {
  if (!layout || width == 0)
    return std::nullopt;
  Operation *producer = handle.getDefiningOp();
  if (!producer)
    return std::nullopt;
  // IEEE 1800-2023 7.4.5, 11.5.1: any invalid enclosing index denotes no
  // storage. Retain every guard and handle-offset validity check when
  // resolving nested aggregate fields to one fixed physical root.
  SmallVector<Value> guards, amounts;
  NativeHandleChain chain = getNativeHandleChain(handle);
  for (const NativeHandleLink &link : chain.links) {
    if (const auto *offset = std::get_if<NativeHandleOffset>(&link)) {
      amounts.push_back(offset->amount);
      continue;
    }
    guards.push_back(std::get<NativeHandleGuard>(link).valid);
  }
  Value root = chain.root;
  if (amounts.empty() || (guards.empty() && (!access || !access->inBounds)))
    return std::nullopt;
  std::optional<uint64_t> base = resolveCFGConstantInteger(root);
  talos_rt_stable_handle_v1 decoded{};
  if (!base || !talos_rt_stable_handle_decode(*base, &decoded) ||
      decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset < 0)
    return std::nullopt;
  bool direct = layout->directHandles.contains(decoded.id);
  bool guarded = layout->guardedHandles.contains(decoded.id);
  if (!direct && !guarded)
    return std::nullopt;
  const auto *bound = layout->findBound(decoded.id);
  uint64_t localOffset = static_cast<uint64_t>(decoded.offset);
  if (!bound || localOffset > bound->width ||
      width > bound->width - localOffset)
    return std::nullopt;
  OpBuilder builder(producer);
  Location location = producer->getLoc();
  // The sparse handle and dense scoped-index analyses proved every enclosing
  // selection valid, including four-state knownness. Recheck the physical root
  // and stable-handle capacity before using that certificate. IEEE 1800-2023
  // 7.4.5 and 11.5.1 fallbacks remain necessary for every unproved selection.
  bool matches =
      access && access->root == decoded.id && bound->width <= INT32_MAX;
  bool inBounds = matches && access->inBounds;
  bool wholeOrInvalid = matches && access->wholeOrInvalid;
  if (inBounds) {
    auto i64 = builder.getI64Type();
    Value amount = llvmConstant(builder, location, i64, localOffset);
    for (Value next : llvm::reverse(amounts))
      amount = arith::AddIOp::create(builder, location, amount, next);
    return DirectDynamicStateRange{
        llvmConstant(builder, location, builder.getI1Type(), 1),
        amount,
        bound->offset,
        0,
        bound->width,
        decoded.id,
        guarded,
        true,
        true,
        bound->containerWidth};
  }
  // A guard-free handle is admitted only with the matching access proof.
  // Losing a certificate on a rewritten access must keep the generic path.
  if (guards.empty())
    return std::nullopt;
  Value valid = guards.front();
  for (Value next : ArrayRef<Value>(guards).drop_front())
    valid = arith::AndIOp::create(builder, location, valid, next);
  auto i64 = builder.getI64Type();
  Value amount = llvmConstant(builder, location, i64, localOffset);
  for (Value next : llvm::reverse(amounts)) {
    if (wholeOrInvalid) {
      // Typed array/field geometry proves containment when the original
      // index guards pass. No extra clipped-slice or handle-overflow checks
      // are needed on that path; invalid indices still use the guards.
      amount = arith::AddIOp::create(builder, location, amount, next);
      continue;
    }
    Value representable = arith::AndIOp::create(
        builder, location,
        arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::sge, next,
            arith::SubIOp::create(
                builder, location,
                llvmConstant(builder, location, i64, INT32_MIN), amount)),
        arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::sle, next,
            arith::SubIOp::create(
                builder, location,
                llvmConstant(builder, location, i64, INT32_MAX), amount)));
    valid = arith::AndIOp::create(builder, location, valid, representable);
    next = arith::SelectOp::create(builder, location, representable, next,
                                   llvmConstant(builder, location, i64, 0));
    amount = arith::AddIOp::create(builder, location, amount, next);
  }
  return DirectDynamicStateRange{valid,          amount,
                                 bound->offset,  0,
                                 bound->width,   decoded.id,
                                 guarded,        false,
                                 wholeOrInvalid, bound->containerWidth};
}

// Canonical planes own an eight-byte guard after their logical extent (see
// materializeNativeStatePlanes and talos_rt_v1_native_state_initialize).
// A contained or clamped window may therefore use one native scalar access,
// including at the last byte. At most seven extra bytes are touched, and the
// logical value/mask still excludes every neighboring bit and guard byte.
static unsigned getNativePackedWindowWidth(unsigned valueWidth) {
  return valueWidth <= 57 ? llvm::PowerOf2Ceil(valueWidth + 7) : 0;
}

static void annotateCanonicalAccess(Operation *operation, uint64_t rootOffset,
                                    uint64_t rootWidth, unsigned spanWidth) {
  if (rootOffset > UINT64_MAX - rootWidth ||
      rootOffset + rootWidth > UINT64_MAX - 7)
    return;
  uint64_t begin = rootOffset / 8;
  uint64_t end = (rootOffset + rootWidth + 7) / 8;
  uint64_t padding = llvm::divideCeil(spanWidth, 8u);
  if (end > UINT64_MAX - padding)
    return;
  end += padding;
  // IEEE 1800-2023 11.5.1: the selector is contained or explicitly clamped
  // before this access. Include its complete physical window, not merely
  // the logical write mask, so adjacent packed fields cannot go stale.
  setNativeAccessWindow(operation,
                        DenseI64ArrayAttr::get(operation->getContext(),
                                               {int64_t(begin), int64_t(end)}));
}

Value loadDynamicPackedWindow(ConversionPatternRewriter &rewriter,
                              Location location,
                              schedule::StatePlane statePlane,
                              IntegerType resultType, Value absolute,
                              const DirectDynamicStateRange &range) {
  IntegerType i64 = rewriter.getI64Type();
  unsigned minimumSpanWidth = llvm::alignTo(resultType.getWidth(), 8u);
  unsigned maximumSpanWidth = llvm::alignTo(resultType.getWidth() + 7, 8u);
  Value byteOffset = arith::ShRUIOp::create(
      rewriter, location, absolute,
      llvmConstant(rewriter, location, i64, uint64_t{3}));
  Value firstBit =
      arith::AndIOp::create(rewriter, location, absolute,
                            llvmConstant(rewriter, location, i64, uint64_t{7}));
  auto loadSpan = [&](unsigned spanWidth) {
    IntegerType spanType = rewriter.getIntegerType(spanWidth);
    Value span = schedule::NativeStateLoadOp::create(
        rewriter, location, spanType, statePlane, byteOffset, 0, 1);
    annotateCanonicalAccess(span.getDefiningOp(), range.rootOffset,
                            range.rootWidth, spanWidth);
    Value firstBitShift =
        spanWidth == 64 ? firstBit
        : spanWidth < 64
            ? LLVM::TruncOp::create(rewriter, location, spanType, firstBit)
                  .getResult()
            : LLVM::ZExtOp::create(rewriter, location, spanType, firstBit)
                  .getResult();
    Value shifted =
        arith::ShRUIOp::create(rewriter, location, span, firstBitShift);
    return spanType == resultType
               ? shifted
               : LLVM::TruncOp::create(rewriter, location, resultType, shifted)
                     .getResult();
  };
  // Canonical planes carry padding bytes past their roots for word accesses.
  if (schedule::isCanonicalStatePlane(statePlane))
    if (unsigned nativeWidth =
            getNativePackedWindowWidth(resultType.getWidth()))
      return loadSpan(nativeWidth);
  if (minimumSpanWidth == maximumSpanWidth)
    return loadSpan(minimumSpanWidth);
  {
    Block *load = rewriter.getInsertionBlock();
    Block *continuation =
        rewriter.splitBlock(load, rewriter.getInsertionPoint());
    Region *region = load->getParent();
    Block *narrow = rewriter.createBlock(region, continuation->getIterator());
    Block *wide = rewriter.createBlock(region, continuation->getIterator());
    Block *loadedJoin = continuation;
    BlockArgument joined = loadedJoin->addArgument(resultType, location);
    rewriter.setInsertionPointToEnd(load);
    Value useNarrow = arith::CmpIOp::create(
        rewriter, location, arith::CmpIPredicate::ule, firstBit,
        llvmConstant(rewriter, location, i64,
                     minimumSpanWidth - resultType.getWidth()));
    cf::CondBranchOp::create(rewriter, location, useNarrow, narrow,
                             ValueRange{}, wide, ValueRange{});
    rewriter.setInsertionPointToEnd(narrow);
    Value narrowValue = loadSpan(minimumSpanWidth);
    cf::BranchOp::create(rewriter, location, loadedJoin,
                         ValueRange{narrowValue});
    rewriter.setInsertionPointToEnd(wide);
    Value wideValue = loadSpan(maximumSpanWidth);
    cf::BranchOp::create(rewriter, location, loadedJoin, ValueRange{wideValue});
    rewriter.setInsertionPointToStart(loadedJoin);
    return joined;
  }
}

Value loadDirectDynamicPackedPlane(ConversionPatternRewriter &rewriter,
                                   Location location,
                                   schedule::StatePlane statePlane,
                                   IntegerType resultType,
                                   const DirectDynamicStateRange &range,
                                   bool unknownFallback,
                                   std::optional<PackedAccessUnit> unit = {}) {
  IntegerType i64 = rewriter.getI64Type();
  if (range.wholeOrInvalid && !range.inBounds) {
    // Keep the source array check in front of its memory access, like Clang's
    // lowering of an explicitly bounds-checked element. Invalid indices have
    // no partially overlapping bits and must produce the SV fallback value.
    Block *head = rewriter.getInsertionBlock();
    Block *join = rewriter.splitBlock(head, rewriter.getInsertionPoint());
    Value result = join->addArgument(resultType, location);
    Block *load = rewriter.createBlock(head->getParent(), join->getIterator());
    Block *fallback =
        rewriter.createBlock(head->getParent(), join->getIterator());
    rewriter.setInsertionPointToEnd(head);
    cf::CondBranchOp::create(rewriter, location, range.valid, load, fallback);
    rewriter.setInsertionPointToEnd(load);
    DirectDynamicStateRange contained = range;
    contained.inBounds = true;
    Value value =
        loadDirectDynamicPackedPlane(rewriter, location, statePlane, resultType,
                                     contained, unknownFallback, unit);
    cf::BranchOp::create(rewriter, location, join, ValueRange{value});
    rewriter.setInsertionPointToEnd(fallback);
    Value invalid = arith::ConstantOp::create(
        rewriter, location, resultType,
        rewriter.getIntegerAttr(resultType,
                                unknownFallback
                                    ? APInt::getAllOnes(resultType.getWidth())
                                    : APInt(resultType.getWidth(), 0)));
    cf::BranchOp::create(rewriter, location, join, ValueRange{invalid});
    rewriter.setInsertionPointToStart(join);
    return result;
  }
  if (unit) {
    // The typed record field and its byte-address certificate determine
    // a fixed unit before lowering erases the type. Sibling fields share
    // one address, integer width and constant field shift, as in Clang.
    Value offset = arith::SubIOp::create(
        rewriter, location, range.bitOffset,
        llvmConstant(rewriter, location, i64, unit->bitOffset));
    Value absolute = arith::AddIOp::create(
        rewriter, location, offset,
        llvmConstant(rewriter, location, i64,
                     range.rootOffset + range.localOffset));
    auto storageType = rewriter.getIntegerType(unit->width);
    Value byte = arith::ShRUIOp::create(
        rewriter, location, absolute, llvmConstant(rewriter, location, i64, 3));
    Value storage = schedule::NativeStateLoadOp::create(
        rewriter, location, storageType, statePlane, byte, 0, 1);
    if (range.inBounds)
      annotateCanonicalAccess(storage.getDefiningOp(), range.rootOffset,
                              range.rootWidth, storageType.getWidth());
    Value shifted = arith::ShRUIOp::create(
        rewriter, location, storage,
        llvmConstant(rewriter, location, storageType, unit->bitOffset));
    Value result = resizeNativeInteger(rewriter, location, shifted, resultType);
    return result;
  }
  if (range.inBounds) {
    // A proved contained selector in a register-sized root can read the same
    // canonical word used by its updates. Keep a constant physical address so
    // activation-local memory SSA can carry reductions through their CFG.
    // The bounds certificate concerns selectors only; both value/unknown
    // planes independently retain their contents (LRM 7.4.5, 11.5.1).
    if (range.rootWidth <= 64) {
      auto rootType = rewriter.getIntegerType(range.rootWidth);
      Value root = extractDirectPackedPlane(
          rewriter, location,
          loadDirectPackedPlane(rewriter, location, statePlane,
                                range.rootOffset, range.rootWidth,
                                range.containerWidth),
          rootType);
      Value offset = arith::AddIOp::create(
          rewriter, location, range.bitOffset,
          llvmConstant(rewriter, location, i64, range.localOffset));
      if (rootType != i64)
        offset = LLVM::TruncOp::create(rewriter, location, rootType, offset);
      Value selected = arith::ShRUIOp::create(rewriter, location, root, offset);
      return rootType == resultType
                 ? selected
                 : LLVM::TruncOp::create(rewriter, location, resultType,
                                         selected)
                       .getResult();
    }
    Value absolute = arith::AddIOp::create(
        rewriter, location, range.bitOffset,
        llvmConstant(rewriter, location, i64,
                     range.rootOffset + range.localOffset));
    return loadDynamicPackedWindow(rewriter, location, statePlane, resultType,
                                   absolute, range);
  }
  Value zero = llvmConstant(rewriter, location, i64, 0);
  Value minimum = llvmConstant(
      rewriter, location, i64,
      static_cast<uint64_t>(-static_cast<int64_t>(resultType.getWidth() - 1)));
  Value maximum = llvmConstant(rewriter, location, i64, range.rootWidth - 1);
  Value overlapsLow = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::sge, range.bitOffset, minimum);
  Value overlapsHigh = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::sle, range.bitOffset, maximum);
  Value encodesLow = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::sge, range.bitOffset,
      llvmConstant(rewriter, location, i64, static_cast<uint64_t>(INT32_MIN)));
  Value encodesHigh = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::sle, range.bitOffset,
      llvmConstant(rewriter, location, i64, INT32_MAX));
  Value valid = arith::AndIOp::create(
      rewriter, location, range.valid,
      arith::AndIOp::create(
          rewriter, location,
          arith::AndIOp::create(rewriter, location, overlapsLow, overlapsHigh),
          arith::AndIOp::create(rewriter, location, encodesLow, encodesHigh)));

  Block *head = rewriter.getInsertionBlock();
  Block *continuation = rewriter.splitBlock(head, rewriter.getInsertionPoint());
  BlockArgument result = continuation->addArgument(resultType, location);
  Region *region = head->getParent();
  Block *load = rewriter.createBlock(region, continuation->getIterator());
  Block *fallback = rewriter.createBlock(region, continuation->getIterator());
  rewriter.setInsertionPointToEnd(head);
  cf::CondBranchOp::create(rewriter, location, valid, load, ValueRange{},
                           fallback, ValueRange{});

  rewriter.setInsertionPointToEnd(load);
  Value negative = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::slt, range.bitOffset, zero);
  Value nonnegative = arith::SelectOp::create(rewriter, location, negative,
                                              zero, range.bitOffset);
  Value lastFullStart = llvmConstant(rewriter, location, i64,
                                     range.rootWidth - resultType.getWidth());
  Value aboveLastFullStart =
      arith::CmpIOp::create(rewriter, location, arith::CmpIPredicate::ugt,
                            nonnegative, lastFullStart);
  Value clamped = arith::SelectOp::create(
      rewriter, location, aboveLastFullStart, lastFullStart, nonnegative);
  Value delta =
      arith::SubIOp::create(rewriter, location, range.bitOffset, clamped);
  Value deltaNegative = arith::CmpIOp::create(
      rewriter, location, arith::CmpIPredicate::slt, delta, zero);
  Value negatedDelta = arith::SubIOp::create(rewriter, location, zero, delta);
  Value absoluteDelta = arith::SelectOp::create(
      rewriter, location, deltaNegative, negatedDelta, delta);
  Value absolute =
      arith::AddIOp::create(rewriter, location, clamped,
                            llvmConstant(rewriter, location, i64,
                                         range.rootOffset + range.localOffset));
  Value loaded = loadDynamicPackedWindow(rewriter, location, statePlane,
                                         resultType, absolute, range);
  Value resultShift =
      resultType.getWidth() == 64 ? absoluteDelta
      : resultType.getWidth() > 64
          ? LLVM::ZExtOp::create(rewriter, location, resultType, absoluteDelta)
                .getResult()
          : LLVM::TruncOp::create(rewriter, location, resultType, absoluteDelta)
                .getResult();
  Value alignedLeft =
      arith::ShLIOp::create(rewriter, location, loaded, resultShift);
  Value alignedRight =
      arith::ShRUIOp::create(rewriter, location, loaded, resultShift);
  Value aligned = arith::SelectOp::create(rewriter, location, deltaNegative,
                                          alignedLeft, alignedRight);

  IntegerType maskType = rewriter.getIntegerType(resultType.getWidth() + 1);
  Value maskWidth =
      maskType.getWidth() == 64 ? absoluteDelta
      : maskType.getWidth() < 64
          ? LLVM::TruncOp::create(rewriter, location, maskType, absoluteDelta)
                .getResult()
          : LLVM::ZExtOp::create(rewriter, location, maskType, absoluteDelta)
                .getResult();
  Value overlapWidth = arith::SubIOp::create(
      rewriter, location,
      llvmConstant(rewriter, location, maskType, resultType.getWidth()),
      maskWidth);
  Value lowMask = arith::SubIOp::create(
      rewriter, location,
      arith::ShLIOp::create(rewriter, location,
                            llvmConstant(rewriter, location, maskType, 1),
                            overlapWidth),
      llvmConstant(rewriter, location, maskType, 1));
  Value outputStart =
      arith::SelectOp::create(rewriter, location, deltaNegative, maskWidth,
                              llvmConstant(rewriter, location, maskType, 0));
  Value mask = LLVM::TruncOp::create(
      rewriter, location, resultType,
      arith::ShLIOp::create(rewriter, location, lowMask, outputStart));
  Value masked = arith::AndIOp::create(rewriter, location, aligned, mask);
  if (unknownFallback)
    masked = arith::OrIOp::create(
        rewriter, location, masked,
        arith::XOrIOp::create(
            rewriter, location, mask,
            arith::ConstantOp::create(
                rewriter, location, resultType,
                rewriter.getIntegerAttr(
                    resultType, APInt::getAllOnes(resultType.getWidth())))));
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{masked});

  rewriter.setInsertionPointToEnd(fallback);
  APInt fallbackValue = unknownFallback
                            ? APInt::getAllOnes(resultType.getWidth())
                            : APInt(resultType.getWidth(), 0);
  Value invalid = arith::ConstantOp::create(
      rewriter, location, resultType,
      rewriter.getIntegerAttr(resultType, fallbackValue));
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{invalid});
  rewriter.setInsertionPointToStart(continuation);
  return result;
}

DirectPackedPlane loadDirectPackedPlane(OpBuilder &builder, Location location,
                                        schedule::StatePlane statePlane,
                                        uint64_t bitOffset, unsigned width,
                                        unsigned containerWidth, bool read,
                                        std::optional<PackedAccessUnit> unit) {
  uint64_t firstByte = bitOffset / 8;
  unsigned firstBit = static_cast<unsigned>(bitOffset % 8);
  assert(!containerWidth ||
         (firstBit == 0 && containerWidth >= width && containerWidth <= 64));
  unsigned byteCount =
      containerWidth ? containerWidth / 8 : (firstBit + width + 7) / 8;
  if (unit && !containerWidth) {
    firstByte = (bitOffset - unit->bitOffset) / 8;
    firstBit = unit->bitOffset;
    byteCount = unit->width / 8;
  }
  IntegerType spanType = builder.getIntegerType(byteCount * 8);
  Value span;
  if (read)
    span = schedule::NativeStateLoadOp::create(
        builder, location, spanType, statePlane, Value{}, firstByte, 1);
  return {statePlane, firstByte, spanType, span, firstBit};
}

Value extractDirectPackedPlane(OpBuilder &builder, Location location,
                               const DirectPackedPlane &plane,
                               IntegerType resultType) {
  Value shifted = plane.span;
  if (plane.bitOffset != 0)
    shifted = arith::ShRUIOp::create(
        builder, location, shifted,
        llvmConstant(builder, location, plane.spanType, plane.bitOffset));
  if (shifted.getType() == resultType)
    return shifted;
  return LLVM::TruncOp::create(builder, location, resultType, shifted);
}

Value storeDirectPackedPlane(OpBuilder &builder, Location location, Value input,
                             schedule::StatePlane statePlane,
                             uint64_t bitOffset, bool trackChange,
                             unsigned containerWidth = 0,
                             std::optional<PackedAccessUnit> unit = {}) {
  IntegerType inputType = cast<IntegerType>(input.getType());
  bool wholeUnit =
      containerWidth ||
      (unit ? unit->bitOffset == 0 &&
                  (unit->width == inputType.getWidth() || unit->ownsPadding)
            : bitOffset % 8 == 0 && inputType.getWidth() % 8 == 0);
  DirectPackedPlane plane = loadDirectPackedPlane(
      builder, location, statePlane, bitOffset, inputType.getWidth(),
      containerWidth, !wholeUnit || trackChange, unit);
  if (wholeUnit) {
    // Like Clang, a value filling its access unit needs no read/modify/write.
    // A complete logical root also owns its allocation padding and may fill
    // it by zero-extension. Partial fields retain masked updates below.
    Value extended =
        inputType == plane.spanType
            ? input
            : LLVM::ZExtOp::create(builder, location, plane.spanType, input);
    plane.store(builder, location, extended);
    if (!trackChange)
      return llvmConstant(builder, location, builder.getI1Type(), 0);
    Value old = extractDirectPackedPlane(builder, location, plane, inputType);
    return arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                 old, input);
  }
  APInt fieldMask =
      APInt::getBitsSet(plane.spanType.getWidth(), plane.bitOffset,
                        plane.bitOffset + inputType.getWidth());
  Value mask = arith::ConstantOp::create(
      builder, location, plane.spanType,
      builder.getIntegerAttr(plane.spanType, fieldMask));
  Value preserved = arith::AndIOp::create(
      builder, location, plane.span,
      arith::XOrIOp::create(
          builder, location, mask,
          arith::ConstantOp::create(
              builder, location, plane.spanType,
              builder.getIntegerAttr(
                  plane.spanType,
                  APInt::getAllOnes(plane.spanType.getWidth())))));
  Value extended =
      inputType == plane.spanType
          ? input
          : LLVM::ZExtOp::create(builder, location, plane.spanType, input);
  if (plane.bitOffset != 0)
    extended = arith::ShLIOp::create(
        builder, location, extended,
        llvmConstant(builder, location, plane.spanType, plane.bitOffset));
  Value updated = arith::OrIOp::create(
      builder, location, preserved,
      arith::AndIOp::create(builder, location, extended, mask));
  plane.store(builder, location, updated);
  if (!trackChange)
    return llvmConstant(builder, location, builder.getI1Type(), 0);
  Value old = extractDirectPackedPlane(builder, location, plane, inputType);
  return arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne, old,
                               input);
}

} // namespace detail

namespace detail {

Value tryLoadSelectedStaticStatePlane(OpBuilder &builder, Location location,
                                      Value handle, IntegerType resultType,
                                      schedule::StatePlane statePlane,
                                      const NativeStateLayout *directLayout,
                                      bool assumeClean, bool knownZero,
                                      llvm::function_ref<Value(Value)> remap,
                                      uint64_t additionalOffset) {
  // CFG canonicalization can merge reads into selects or block arguments of
  // distinct handles. Every incoming leaf must be in bounds and free of
  // runtime overlays before its read can be speculated. Keep the loads at the
  // original read, so changes on predecessor paths are observed there.
  auto selected = [](Value value) -> Operation * {
    Operation *op = value.getDefiningOp();
    return isa_and_nonnull<arith::SelectOp, LLVM::SelectOp>(op) ? op : nullptr;
  };
  if (selected(handle) || isa<BlockArgument>(handle)) {
    SmallVector<std::pair<uint64_t, DirectStaticStateRange>, 4> leaves;
    DenseSet<uint64_t> leafHandles;
    DenseSet<Value> visited;
    SmallVector<Value> pending{handle};
    bool direct = true;
    while (!pending.empty() && direct) {
      // Predecessor operands can still reference replaced operations or block
      // arguments until dialect conversion commits its pending rewrites.
      Value current = pending.pop_back_val();
      if (remap)
        current = remap(current);
      if (!current) {
        direct = false;
        break;
      }
      if (!visited.insert(current).second)
        continue;
      // Follow block arguments ourselves, including cycles and joins with
      // distinct incoming constants.
      auto leaf = isa<BlockArgument>(current)
                      ? std::nullopt
                      : resolveDirectStaticStateRange(
                            current, resultType.getWidth(), directLayout);
      if (leaf && (!leaf->guarded || assumeClean)) {
        if (additionalOffset) {
          const auto *bound = directLayout->findBound(leaf->staticID);
          if (!bound || leaf->localOffset > uint64_t{INT32_MAX} ||
              additionalOffset > uint64_t{INT32_MAX} - leaf->localOffset ||
              additionalOffset > bound->width - leaf->localOffset ||
              resultType.getWidth() >
                  bound->width - leaf->localOffset - additionalOffset) {
            direct = false;
            break;
          }
          leaf->offset += additionalOffset;
          leaf->localOffset += additionalOffset;
          leaf->containerWidth = 0;
          leaf->accessUnit =
              directLayout->packedStorage
                  ? directLayout->packedStorage->get(
                        bound->type, bound->offset, leaf->localOffset,
                        resultType.getWidth())
                  : std::nullopt;
        }
        uint64_t encoded = *resolveCFGConstantInteger(current);
        if (leafHandles.insert(encoded).second)
          leaves.emplace_back(encoded, *leaf);
      } else if (Operation *select = selected(current)) {
        pending.push_back(select->getOperand(1));
        pending.push_back(select->getOperand(2));
      } else if (auto argument = dyn_cast<BlockArgument>(current)) {
        Block *block = argument.getOwner();
        if (block->hasNoPredecessors()) {
          direct = false;
          break;
        }
        for (Block *predecessor : block->getPredecessors()) {
          Operation *terminator = predecessor->getTerminator();
          auto branch = dyn_cast<BranchOpInterface>(terminator);
          if (!branch) {
            direct = false;
            break;
          }
          for (unsigned successor = 0;
               successor != terminator->getNumSuccessors(); ++successor) {
            if (terminator->getSuccessor(successor) != block)
              continue;
            auto operands = branch.getSuccessorOperands(successor);
            unsigned index = argument.getArgNumber();
            if (index >= operands.size() || operands.isOperandProduced(index)) {
              direct = false;
              break;
            }
            pending.push_back(operands[index]);
          }
          if (!direct)
            break;
        }
      } else {
        direct = false;
      }
    }
    if (direct && !leaves.empty()) {
      if (knownZero)
        return llvmConstant(builder, location, resultType, 0);
      Value result;
      for (const auto &[encoded, range] : leaves) {
        Value loaded = extractDirectPackedPlane(
            builder, location,
            loadDirectPackedPlane(builder, location, statePlane, range.offset,
                                  resultType.getWidth(), range.containerWidth,
                                  true, range.accessUnit),
            resultType);
        if (!result) {
          result = loaded;
          continue;
        }
        Value matches = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::eq, handle,
            llvmConstant(builder, location, handle.getType(), encoded));
        result =
            arith::SelectOp::create(builder, location, matches, loaded, result);
      }
      return result;
    }
  }
  return {};
}

Value loadStatePlane(ConversionPatternRewriter &rewriter, Location location,
                     Value handle, IntegerType resultType,
                     schedule::StatePlane statePlane, bool unknownFallback,
                     uint64_t stateBitCount,
                     const NativeStateLayout *directLayout,
                     Value guardedPermission, bool assumeClean,
                     const NativeStateAccessInfo *access) {
  auto accessUnit = access ? access->accessUnit : std::nullopt;
  std::optional<DirectStaticStateRange> range = resolveDirectStaticStateRange(
      handle, resultType.getWidth(), directLayout);
  if (range && (!range->guarded || assumeClean))
    return extractDirectPackedPlane(
        rewriter, location,
        loadDirectPackedPlane(rewriter, location, statePlane, range->offset,
                              resultType.getWidth(), range->containerWidth,
                              true, range->accessUnit),
        resultType);
  if (Value selected = tryLoadSelectedStaticStatePlane(
          rewriter, location, handle, resultType, statePlane, directLayout,
          assumeClean, false,
          [&](Value value) { return rewriter.getRemappedValue(value); }))
    return selected;
  std::optional<DirectDynamicStateRange> dynamicRange =
      resolveDirectDynamicStateRange(handle, resultType.getWidth(),
                                     directLayout, access);
  if (dynamicRange && (!access || access->root != dynamicRange->staticID ||
                       !dynamicRange->wholeOrInvalid))
    accessUnit.reset();
  if (dynamicRange && (!dynamicRange->guarded || assumeClean))
    return loadDirectDynamicPackedPlane(rewriter, location, statePlane,
                                        resultType, *dynamicRange,
                                        unknownFallback, accessUnit);

  auto emitGeneric = [&]() -> Value {
    // The runtime reads through the handle. A bit the handle does not name
    // reads as X (IEEE 1800-2023 7.4.5, 11.5.1), which is the
    // `unknownFallback` every caller passes for the direct paths above.
    return schedule::NativeStateLoadHandleOp::create(
        rewriter, location, resultType, statePlane, handle, stateBitCount);
  };
  if ((!range || !range->guarded) && (!dynamicRange || !dynamicRange->guarded))
    return emitGeneric();

  Block *head = rewriter.getInsertionBlock();
  Block *continuation = rewriter.splitBlock(head, rewriter.getInsertionPoint());
  BlockArgument result = continuation->addArgument(resultType, location);
  Region *region = head->getParent();
  Block *directBlock =
      rewriter.createBlock(region, continuation->getIterator());
  Block *genericBlock =
      rewriter.createBlock(region, continuation->getIterator());

  rewriter.setInsertionPointToEnd(head);
  Value useDirect = guardedPermission
                        ? guardedPermission
                        : staticSpecializationGuard(
                              rewriter, location,
                              range ? range->staticID : dynamicRange->staticID,
                              TALOS_RT_STATIC_ROOT_READ);
  markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useDirect,
                                          directBlock, ValueRange{},
                                          genericBlock, ValueRange{}));

  rewriter.setInsertionPointToEnd(directBlock);
  // The guard certifies storage addressing, not the selected value's
  // knownness. Keep the dynamic range's own bounds and X/Z fallback checks.
  Value direct =
      range ? extractDirectPackedPlane(
                  rewriter, location,
                  loadDirectPackedPlane(rewriter, location, statePlane,
                                        range->offset, resultType.getWidth(),
                                        range->containerWidth, true,
                                        range->accessUnit),
                  resultType)
            : loadDirectDynamicPackedPlane(rewriter, location, statePlane,
                                           resultType, *dynamicRange,
                                           unknownFallback, accessUnit);
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{direct});

  rewriter.setInsertionPointToEnd(genericBlock);
  Value generic = emitGeneric();
  cf::BranchOp::create(rewriter, location, continuation, ValueRange{generic});

  rewriter.setInsertionPointToStart(continuation);
  return result;
}

Value storeStatePlane(ConversionPatternRewriter &rewriter, Location location,
                      Value handle, Value input,
                      schedule::StatePlane statePlane, uint64_t stateBitCount,
                      const NativeStateLayout *directLayout,
                      Value guardedPermission, bool assumeClean,
                      bool trackChange, bool continuous) {
  IntegerType inputType = cast<IntegerType>(input.getType());
  std::optional<DirectStaticStateRange> range =
      resolveDirectStaticStateRange(handle, inputType.getWidth(), directLayout);
  if (range && continuous && (assumeClean || !range->guarded) &&
      directLayout->directContinuous) {
    // Keep the actual contribution even when no writer is attached. These
    // pointers bind the runtime's own retained planes, so a later force,
    // deposit, or release needs neither reconstruction nor a shadow import.
    schedule::StatePlane retained =
        statePlane == schedule::StatePlane::Unknown
            ? schedule::StatePlane::ContributionUnknown
            : schedule::StatePlane::ContributionValue;
    storeDirectPackedPlane(rewriter, location, input, retained, range->offset,
                           false, range->containerWidth, range->accessUnit);
    if (statePlane == schedule::StatePlane::Value) {
      Value mask = arith::ConstantOp::create(
          rewriter, location, inputType,
          rewriter.getIntegerAttr(inputType,
                                  APInt::getAllOnes(inputType.getWidth())));
      storeDirectPackedPlane(
          rewriter, location, mask, schedule::StatePlane::ContributionMask,
          range->offset, false, range->containerWidth, range->accessUnit);
    }
    return storeDirectPackedPlane(rewriter, location, input, statePlane,
                                  range->offset, trackChange,
                                  range->containerWidth, range->accessUnit);
  }
  // Unguarded roots can never be forced or procedurally assigned, so they do
  // not need a retained continuous value for release. Guarded continuous
  // roots still need the runtime path even in an assume-clean specialization:
  // the clean publication may precede a later force.
  if (range && (!range->guarded || (!continuous && assumeClean)))
    return storeDirectPackedPlane(rewriter, location, input, statePlane,
                                  range->offset, trackChange,
                                  range->containerWidth, range->accessUnit);

  auto emitGeneric = [&]() -> Value {
    return schedule::NativeStateStoreHandleOp::create(
        rewriter, location, input, statePlane, handle, stateBitCount,
        continuous);
  };
  if (continuous || !range || !range->guarded)
    return emitGeneric();

  Block *head = rewriter.getInsertionBlock();
  Block *continuation = rewriter.splitBlock(head, rewriter.getInsertionPoint());
  BlockArgument changed =
      continuation->addArgument(rewriter.getI1Type(), location);
  Region *region = head->getParent();
  Block *directBlock =
      rewriter.createBlock(region, continuation->getIterator());
  Block *genericBlock =
      rewriter.createBlock(region, continuation->getIterator());

  rewriter.setInsertionPointToEnd(head);
  Value useDirect =
      guardedPermission
          ? guardedPermission
          : staticSpecializationGuard(rewriter, location, range->staticID,
                                      TALOS_RT_STATIC_ROOT_WRITE);
  markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useDirect,
                                          directBlock, ValueRange{},
                                          genericBlock, ValueRange{}));

  rewriter.setInsertionPointToEnd(directBlock);
  Value directChanged = storeDirectPackedPlane(
      rewriter, location, input, statePlane, range->offset, trackChange,
      range->containerWidth, range->accessUnit);
  cf::BranchOp::create(rewriter, location, continuation,
                       ValueRange{directChanged});

  rewriter.setInsertionPointToEnd(genericBlock);
  Value genericChanged = emitGeneric();
  cf::BranchOp::create(rewriter, location, continuation,
                       ValueRange{genericChanged});

  rewriter.setInsertionPointToStart(continuation);
  return changed;
}

bool emitDirectDynamicPackedStore(
    ConversionPatternRewriter &rewriter, Location location, Value handle,
    Value value, Value unknown, const NativeStateLayout *layout,
    bool assumeClean, bool continuous, bool twoState,
    schedule::SourceOwnerAttr sourceOwner, const NativeStateAccessInfo *access,
    bool nbaEquivalent) {
  auto accessUnit = access ? access->accessUnit : std::nullopt;
  auto inputType = dyn_cast<IntegerType>(value.getType());
  if (!inputType || !layout || !layout->transitionHandlesExact)
    return false;
  auto range = resolveDirectDynamicStateRange(handle, inputType.getWidth(),
                                              layout, access);
  if (!range || (range->guarded && (continuous || !assumeClean)))
    return false;
  bool needsNotification = layout->transitionHandles.contains(range->staticID);
  if (auto function = rewriter.getInsertionBlock()->getParentOp())
    if (auto roots = native::get<native::NoTransitionRoots>(function))
      needsNotification &= !llvm::is_contained(
          roots.asArrayRef(), static_cast<int32_t>(range->staticID));
  if (!access || access->root != range->staticID || !range->wholeOrInvalid)
    accessUnit.reset();
  if (range->rootWidth > 64 || accessUnit) {
    Block *guardContinuation = nullptr;
    if (range->wholeOrInvalid && !range->inBounds) {
      // A typed array access denotes a complete element or no storage. Emit
      // the ordinary guarded store shape: if valid, update the element. Invalid
      // indices must not cause a dummy read/modify/write or a notification.
      Block *head = rewriter.getInsertionBlock();
      guardContinuation =
          rewriter.splitBlock(head, rewriter.getInsertionPoint());
      Block *body = rewriter.createBlock(head->getParent(),
                                         guardContinuation->getIterator());
      rewriter.setInsertionPointToEnd(head);
      cf::CondBranchOp::create(rewriter, location, range->valid, body,
                               guardContinuation);
      rewriter.setInsertionPointToEnd(body);
      range->inBounds = true;
      range->valid = llvmConstant(rewriter, location, rewriter.getI1Type(), 1);
    }
    // Update only the selected bits, independently of the aggregate root's
    // size. Clip partial and invalid selects exactly as LRM 11.5.1
    // requires, and publish after both planes have been stored (4.6(a)).
    auto i64 = rewriter.getI64Type();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Value zero = llvmConstant(rewriter, location, i64, 0);
    Value offset = range->bitOffset;
    Value valid = range->valid, clamped = offset, lowClip = zero,
          highClip = zero;
    if (!range->inBounds) {
      valid = arith::AndIOp::create(
          rewriter, location, range->valid,
          arith::AndIOp::create(
              rewriter, location,
              arith::CmpIOp::create(
                  rewriter, location, arith::CmpIPredicate::sgt, offset,
                  llvmConstant(rewriter, location, i64,
                               -int64_t(inputType.getWidth()))),
              arith::CmpIOp::create(
                  rewriter, location, arith::CmpIPredicate::slt, offset,
                  llvmConstant(rewriter, location, i64, range->rootWidth))));
      Value safe =
          arith::SelectOp::create(rewriter, location, valid, offset, zero);
      Value negative = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::slt, safe, zero);
      Value last = llvmConstant(rewriter, location, i64,
                                range->rootWidth - inputType.getWidth());
      Value above = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::sgt, safe, last);
      clamped = arith::SelectOp::create(
          rewriter, location, above, last,
          arith::SelectOp::create(rewriter, location, negative, zero, safe));
      lowClip = arith::SelectOp::create(
          rewriter, location, negative,
          arith::SubIOp::create(rewriter, location, zero, safe), zero);
      highClip = arith::SelectOp::create(
          rewriter, location, above,
          arith::SubIOp::create(rewriter, location, safe, last), zero);
    }
    Value absolute = arith::AddIOp::create(
        rewriter, location, clamped,
        llvmConstant(rewriter, location, i64, range->rootOffset));
    if (accessUnit)
      absolute = arith::SubIOp::create(
          rewriter, location, absolute,
          llvmConstant(rewriter, location, i64, accessUnit->bitOffset));
    Value byte = arith::ShRUIOp::create(
        rewriter, location, absolute, llvmConstant(rewriter, location, i64, 3));
    Value bit = arith::AndIOp::create(rewriter, location, absolute,
                                      llvmConstant(rewriter, location, i64, 7));
    Value fieldBit = accessUnit ? llvmConstant(rewriter, location, i64,
                                               accessUnit->bitOffset)
                                : bit;
    unsigned accessWidth =
        accessUnit ? accessUnit->width : inputType.getWidth();
    unsigned nativeWindowWidth = accessUnit
                                     ? accessUnit->width
                                     : getNativePackedWindowWidth(accessWidth);
    auto windowType = rewriter.getIntegerType(
        nativeWindowWidth ? nativeWindowWidth
                          : llvm::alignTo(accessWidth + 7, uint64_t{8}));
    auto resize = [&](Value value, IntegerType type) -> Value {
      if (value.getType() == type)
        return value;
      return cast<IntegerType>(value.getType()).getWidth() < type.getWidth()
                 ? LLVM::ZExtOp::create(rewriter, location, type, value)
                       .getResult()
                 : LLVM::TruncOp::create(rewriter, location, type, value)
                       .getResult();
    };
    Value left = resize(highClip, windowType);
    Value right = resize(lowClip, windowType);
    Value shift = resize(fieldBit, windowType);
    Value payloadMask = arith::ConstantOp::create(
        rewriter, location, windowType,
        rewriter.getIntegerAttr(
            windowType,
            APInt::getLowBitsSet(windowType.getWidth(), inputType.getWidth())));
    Value mask = arith::ShLIOp::create(
        rewriter, location,
        arith::ShRUIOp::create(rewriter, location, payloadMask, right), left);
    // The high-clipped target is shifted back into a complete in-root
    // window. Discard mask bits beyond that window before positioning it in
    // the plane; otherwise a select crossing the root's end writes into the
    // next packed variable (IEEE 1800-2023 11.5.1).
    mask = arith::AndIOp::create(rewriter, location, mask, payloadMask);
    mask = arith::ShLIOp::create(rewriter, location, mask, shift);
    mask = arith::SelectOp::create(
        rewriter, location, valid, mask,
        llvmConstant(rewriter, location, windowType, 0));
    // Typed accesses to a plane's window at the dynamic byte.
    auto store = [&](schedule::StatePlane statePlane, Value input) {
      Value positioned = input
                             ? resize(input, windowType)
                             : llvmConstant(rewriter, location, windowType, 0);
      positioned = arith::ShLIOp::create(
          rewriter, location,
          arith::ShLIOp::create(
              rewriter, location,
              arith::ShRUIOp::create(rewriter, location, positioned, right),
              left),
          shift);
      auto writeWindow = [&](unsigned width) {
        auto spanType = rewriter.getIntegerType(width);
        bool wholeUnit = accessUnit && accessUnit->bitOffset == 0 &&
                         (inputType.getWidth() == accessUnit->width ||
                          accessUnit->ownsPadding);
        bool readOld = !wholeUnit || needsNotification;
        Value old = llvmConstant(rewriter, location, windowType, 0);
        if (readOld) {
          auto load = schedule::NativeStateLoadOp::create(
              rewriter, location, spanType, statePlane, byte, 0, 1);
          annotateCanonicalAccess(load, range->rootOffset, range->rootWidth,
                                  width);
          old = resize(load, windowType);
        }
        Value updated;
        if (wholeUnit) {
          updated = positioned;
        } else {
          updated = arith::XOrIOp::create(
              rewriter, location, old,
              arith::AndIOp::create(
                  rewriter, location, mask,
                  arith::XOrIOp::create(rewriter, location, old, positioned)));
        }
        auto write = schedule::NativeStateStoreOp::create(
            rewriter, location, resize(updated, spanType), statePlane, byte, 0,
            1);
        annotateCanonicalAccess(write, range->rootOffset, range->rootWidth,
                                width);
        // The clipped mask preserves every bit outside the root, including
        // neighboring bits in the first and last byte. Retain that proof for
        // promotion bookkeeping even though the byte address is dynamic.
        if (statePlane == schedule::StatePlane::Unknown)
          setNativeAccessWrittenBits(write, rewriter.getDenseI64ArrayAttr(
                                                {int64_t(range->rootOffset),
                                                 int64_t(range->rootWidth)}));
        return std::pair<Value, Value>{
            resize(arith::ShRUIOp::create(rewriter, location, old, shift),
                   inputType),
            resize(arith::ShRUIOp::create(rewriter, location, updated, shift),
                   inputType)};
      };
      unsigned minimumWidth = llvm::alignTo(accessWidth, uint64_t{8});
      if (nativeWindowWidth)
        return writeWindow(nativeWindowWidth);
      if (minimumWidth == windowType.getWidth())
        return writeWindow(minimumWidth);
      // Larger windows retain byte-precise accesses. The native scalar guard
      // proof does not apply to them.
      Block *head = rewriter.getInsertionBlock();
      Block *join = rewriter.splitBlock(head, rewriter.getInsertionPoint());
      Value old = join->addArgument(inputType, location);
      Value updated = join->addArgument(inputType, location);
      Block *narrow =
          rewriter.createBlock(head->getParent(), join->getIterator());
      Block *wide =
          rewriter.createBlock(head->getParent(), join->getIterator());
      rewriter.setInsertionPointToEnd(head);
      Value needsWide = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::ugt, bit,
          llvmConstant(rewriter, location, i64, minimumWidth - accessWidth));
      cf::CondBranchOp::create(rewriter, location, needsWide, wide, narrow);
      for (auto [block, width] : {std::pair{narrow, minimumWidth},
                                  std::pair{wide, windowType.getWidth()}}) {
        rewriter.setInsertionPointToEnd(block);
        auto [previous, next] = writeWindow(width);
        cf::BranchOp::create(rewriter, location, join,
                             ValueRange{previous, next});
      }
      rewriter.setInsertionPointToStart(join);
      return std::pair<Value, Value>{old, updated};
    };
    auto [oldValue, newValue] = store(schedule::StatePlane::Value, value);
    Value oldUnknown = llvmConstant(rewriter, location, inputType, 0);
    Value newUnknown = oldUnknown;
    if (!twoState)
      std::tie(oldUnknown, newUnknown) =
          store(schedule::StatePlane::Unknown, unknown);
    if (needsNotification) {
      Value context = LLVM::LoadOp::create(
          rewriter, location, pointer,
          LLVM::AddressOfOp::create(rewriter, location, pointer,
                                    "__talos_current_context"),
          8);
      for (unsigned low = 0; low < inputType.getWidth(); low += 64) {
        unsigned width = std::min(64u, inputType.getWidth() - low);
        auto chunk = [&](Value value) -> Value {
          if (low)
            value = arith::ShRUIOp::create(
                rewriter, location, value,
                llvmConstant(rewriter, location, inputType, low));
          value = resize(value, rewriter.getIntegerType(width));
          return resize(value, i64);
        };
        auto transition = schedule::NativeTransitionOp::create(
            rewriter, location, context,
            arith::AddIOp::create(rewriter, location, clamped,
                                  llvmConstant(rewriter, location, i64, low)),
            chunk(oldValue), chunk(oldUnknown), chunk(newValue),
            chunk(newUnknown), rewriter.getI64IntegerAttr(range->staticID),
            rewriter.getI64IntegerAttr(width), sourceOwner);
        if (nbaEquivalent)
          ::talos::schedule::set<
              ::talos::schedule::Field::EvalNbaEquivalentStore>(
              transition, rewriter.getUnitAttr());
      }
    }
    if (guardContinuation) {
      cf::BranchOp::create(rewriter, location, guardContinuation);
      rewriter.setInsertionPointToStart(guardContinuation);
    }
    return true;
  }
  // One machine-word root permits an exact read/modify/write without a
  // runtime handle lookup. Invalid selects are no-ops; overhanging selects
  // update only their in-range bits (LRM 11.5.1).
  auto i64 = rewriter.getI64Type();
  auto rootType = rewriter.getIntegerType(range->rootWidth);
  Value zero = llvmConstant(rewriter, location, i64, 0);
  Value offset = range->bitOffset;
  Value valid = range->valid, right = zero, left = offset;
  if (range->wholeOrInvalid && !range->inBounds) {
    left = arith::SelectOp::create(rewriter, location, valid, offset, zero);
  } else if (!range->inBounds) {
    Value aboveBegin = arith::CmpIOp::create(
        rewriter, location, arith::CmpIPredicate::sgt, offset,
        llvmConstant(rewriter, location, i64, -int64_t(inputType.getWidth())));
    Value belowEnd = arith::CmpIOp::create(
        rewriter, location, arith::CmpIPredicate::slt, offset,
        llvmConstant(rewriter, location, i64, range->rootWidth));
    valid = arith::AndIOp::create(
        rewriter, location, range->valid,
        arith::AndIOp::create(rewriter, location, aboveBegin, belowEnd));
    // Sanitize before either shift, not merely before the final select.
    Value safe =
        arith::SelectOp::create(rewriter, location, valid, offset, zero);
    Value negative = arith::CmpIOp::create(
        rewriter, location, arith::CmpIPredicate::slt, safe, zero);
    right = arith::SelectOp::create(
        rewriter, location, negative,
        arith::SubIOp::create(rewriter, location, zero, safe), zero);
    left = arith::SelectOp::create(rewriter, location, negative, zero, safe);
  }
  Value mask = llvmConstant(rewriter, location, i64,
                            inputType.getWidth() == 64
                                ? UINT64_MAX
                                : (uint64_t{1} << inputType.getWidth()) - 1);
  mask = arith::ShRUIOp::create(rewriter, location, mask, right);
  mask = arith::ShLIOp::create(rewriter, location, mask, left);
  mask = arith::SelectOp::create(rewriter, location, valid, mask, zero);
  auto extend = [&](Value input) -> Value {
    if (!input)
      return zero;
    return input.getType() == i64
               ? input
               : LLVM::ZExtOp::create(rewriter, location, i64, input)
                     .getResult();
  };
  auto load = [&](schedule::StatePlane plane) -> Value {
    return extractDirectPackedPlane(
        rewriter, location,
        loadDirectPackedPlane(rewriter, location, plane, range->rootOffset,
                              range->rootWidth, range->containerWidth),
        rootType);
  };
  auto merge = [&](Value old, Value input) -> Value {
    Value positioned =
        arith::ShRUIOp::create(rewriter, location, extend(input), right);
    positioned = arith::ShLIOp::create(rewriter, location, positioned, left);
    Value previous = extend(old);
    Value merged = arith::XOrIOp::create(
        rewriter, location, previous,
        arith::AndIOp::create(
            rewriter, location, mask,
            arith::XOrIOp::create(rewriter, location, previous, positioned)));
    return rootType == i64
               ? merged
               : LLVM::TruncOp::create(rewriter, location, rootType, merged)
                     .getResult();
  };
  Value oldValue = load(schedule::StatePlane::Value);
  Value newValue = merge(oldValue, value);
  Value oldUnknown = twoState ? llvmConstant(rewriter, location, rootType, 0)
                              : load(schedule::StatePlane::Unknown);
  Value newUnknown = twoState ? oldUnknown : merge(oldUnknown, unknown);
  storeDirectPackedPlane(rewriter, location, newValue,
                         schedule::StatePlane::Value, range->rootOffset, false,
                         range->containerWidth);
  if (!twoState)
    storeDirectPackedPlane(rewriter, location, newUnknown,
                           schedule::StatePlane::Unknown, range->rootOffset,
                           false, range->containerWidth);
  if (needsNotification) {
    Value rootHandle =
        llvmConstant(rewriter, location, i64,
                     talos_rt_stable_handle_encode(
                         TALOS_RT_STABLE_HANDLE_STATIC, range->staticID, 0));
    notifySignal(rewriter, location, rootHandle, range->rootWidth, oldValue,
                 oldUnknown, newValue, newUnknown,
                 DirectStaticStateRange{range->rootOffset, 0, range->staticID,
                                        range->guarded},
                 sourceOwner, nbaEquivalent);
  }
  return true;
}

} // namespace detail

bool isNativeStateHandleAccess(Operation *op) {
  return isa<
      schedule::NativeStateLoadHandleOp, schedule::NativeStateLoadHandleBytesOp,
      schedule::NativeStateStoreHandleOp,
      schedule::NativeStateStoreHandleBytesOp,
      schedule::NativeStateFrameStoreOp, schedule::NativeStateLoadAutomaticOp>(
      op);
}

NativeRuntimeEntry getNativeStateHandleAccessEntry(Operation *access) {
  if (isa<schedule::NativeStateLoadHandleOp,
          schedule::NativeStateLoadHandleBytesOp,
          schedule::NativeStateLoadAutomaticOp>(access))
    return NativeRuntimeEntry::NativeStateLoadPlane;
  if (isa<schedule::NativeStateFrameStoreOp>(access))
    return NativeRuntimeEntry::NativeFrameStore;
  auto store = dyn_cast<schedule::NativeStateStoreHandleOp>(access);
  bool continuous = store
                        ? store.getContinuous()
                        : cast<schedule::NativeStateStoreHandleBytesOp>(access)
                              .getContinuous();
  return continuous ? NativeRuntimeEntry::NativeStateStoreContinuousPlane
                    : NativeRuntimeEntry::NativeStateStorePlane;
}

namespace {
Value loadNativeRuntimeContext(OpBuilder &builder, Location location) {
  Type pointer = LLVM::LLVMPointerType::get(builder.getContext());
  Value address = LLVM::AddressOfOp::create(builder, location, pointer,
                                            "__talos_current_context");
  return LLVM::LoadOp::create(builder, location, pointer, address, 8);
}

// The runtime's frame store takes 64-bit words.
void lowerFrameStore(OpBuilder &builder,
                     schedule::NativeStateFrameStoreOp store) {
  Location location = store.getLoc();
  IntegerType i32 = builder.getI32Type();
  IntegerType i64 = builder.getI64Type();
  auto word = [&](Value bits) -> Value {
    return bits.getType() == i64
               ? bits
               : arith::ExtUIOp::create(builder, location, i64, bits)
                     .getResult();
  };
  bool fourState = store.getFourState();
  Value valuePlane = schedule::NativeStateAddressOp::create(
      builder, location, schedule::StatePlane::Value);
  Value unknownPlane =
      fourState ? schedule::NativeStateAddressOp::create(
                      builder, location, schedule::StatePlane::Unknown)
                      .getResult()
                : LLVM::ZeroOp::create(builder, location, valuePlane.getType())
                      .getResult();
  uint32_t flags =
      (store.getContinuous() ? TALOS_RT_FRAME_STORE_CONTINUOUS : 0) |
      (fourState ? TALOS_RT_FRAME_STORE_UNKNOWN : 0);
  Value unknown = store.getUnknown()
                      ? word(store.getUnknown())
                      : detail::llvmConstant(builder, location, i64, 0);
  unsigned width = store.getValue().getType().getIntOrFloatBitWidth();
  SmallVector<Value, 9> arguments{
      loadNativeRuntimeContext(builder, location),
      valuePlane,
      unknownPlane,
      detail::llvmConstant(builder, location, i64, store.getStateBits()),
      store.getHandle(),
      detail::llvmConstant(builder, location, i32, width),
      detail::llvmConstant(builder, location, i32, flags),
      word(store.getValue()),
      unknown};
  LLVM::CallOp::create(
      builder, location, TypeRange{},
      getNativeRuntimeCallee(builder.getContext(),
                             getNativeStateHandleAccessEntry(store)),
      arguments);
}

// A read of an automatic variable passes no design state: its buffer stands
// in for the plane and the state has no bits.
void lowerAutomaticLoad(OpBuilder &builder,
                        schedule::NativeStateLoadAutomaticOp load) {
  Location location = load.getLoc();
  IntegerType i32 = builder.getI32Type();
  IntegerType i64 = builder.getI64Type();
  SmallVector<Value, 8> arguments{
      load.getRuntimeContext(),
      load.getBuffer(),
      detail::llvmConstant(builder, location, i64, 0),
      load.getHandle(),
      detail::llvmConstant(builder, location, i64, load.getWidth()),
      detail::llvmConstant(builder, location, i32, load.getUnknown()),
      detail::llvmConstant(builder, location, i32, 0),
      load.getBuffer()};
  auto call = LLVM::CallOp::create(
      builder, location, TypeRange{i32},
      getNativeRuntimeCallee(builder.getContext(),
                             getNativeStateHandleAccessEntry(load)),
      arguments);
  load.getStatus().replaceAllUsesWith(call.getResult());
}

// The call of a load or store entry on `plane` at `handle`, moving `width`
// bits through `buffer`; a store sets the byte at `changed`.
void createHandleAccessCall(OpBuilder &builder, Location location,
                            NativeRuntimeEntry entry,
                            schedule::StatePlane plane, Value handle,
                            uint64_t stateBits, uint64_t width, Value buffer,
                            Value changed) {
  IntegerType i32 = builder.getI32Type();
  IntegerType i64 = builder.getI64Type();
  bool unknown = plane == schedule::StatePlane::Unknown;
  Value base = schedule::NativeStateAddressOp::create(builder, location, plane);
  SmallVector<Value, 8> arguments{
      loadNativeRuntimeContext(builder, location),
      base,
      detail::llvmConstant(builder, location, i64, stateBits),
      handle,
      detail::llvmConstant(builder, location, i64, width),
      detail::llvmConstant(builder, location, i32, unknown)};
  if (!changed) {
    // A bit the handle does not name reads as X: 0 in the value plane and 1
    // in the unknown plane (IEEE 1800-2023 7.4.5, 11.5.1).
    arguments.push_back(detail::llvmConstant(builder, location, i32, unknown));
    arguments.push_back(buffer);
  } else {
    arguments.push_back(buffer);
    arguments.push_back(changed);
  }
  LLVM::CallOp::create(builder, location, TypeRange{i32},
                       getNativeRuntimeCallee(builder.getContext(), entry),
                       arguments);
}
} // namespace

void lowerNativeStateHandleAccess(Operation *access) {
  OpBuilder builder(access);
  Location location = access->getLoc();
  NativeRuntimeEntry entry = getNativeStateHandleAccessEntry(access);
  if (auto store = dyn_cast<schedule::NativeStateFrameStoreOp>(access)) {
    lowerFrameStore(builder, store);
  } else if (auto automatic =
                 dyn_cast<schedule::NativeStateLoadAutomaticOp>(access)) {
    lowerAutomaticLoad(builder, automatic);
  } else if (auto load = dyn_cast<schedule::NativeStateLoadHandleOp>(access)) {
    // The runtime reads into a temporary.
    Value out = detail::beginTemporary(builder, location, load.getType(), 1);
    createHandleAccessCall(builder, location, entry, load.getPlane(),
                           load.getHandle(), load.getStateBits(),
                           load.getWidth(), out, Value());
    Value loaded =
        LLVM::LoadOp::create(builder, location, load.getType(), out, 1);
    detail::endTemporary(builder, location, out);
    load.getResult().replaceAllUsesWith(loaded);
  } else if (auto store =
                 dyn_cast<schedule::NativeStateStoreHandleOp>(access)) {
    // The runtime writes from a temporary and reports a change through a
    // byte it leaves 0 when nothing changed.
    IntegerType i8 = builder.getI8Type();
    Value in = detail::beginTemporary(builder, location,
                                      store.getValue().getType(), 1);
    LLVM::StoreOp::create(builder, location, store.getValue(), in, 1);
    Value changed = detail::beginTemporary(builder, location, i8, 1);
    LLVM::StoreOp::create(builder, location,
                          detail::llvmConstant(builder, location, i8, 0),
                          changed, 1);
    createHandleAccessCall(builder, location, entry, store.getPlane(),
                           store.getHandle(), store.getStateBits(),
                           store.getWidth(), in, changed);
    Value changedByte = LLVM::LoadOp::create(builder, location, i8, changed, 1);
    detail::endTemporary(builder, location, in);
    detail::endTemporary(builder, location, changed);
    store.getChanged().replaceAllUsesWith(arith::CmpIOp::create(
        builder, location, arith::CmpIPredicate::ne, changedByte,
        detail::llvmConstant(builder, location, i8, 0)));
  } else if (auto load =
                 dyn_cast<schedule::NativeStateLoadHandleBytesOp>(access)) {
    createHandleAccessCall(builder, location, entry, load.getPlane(),
                           load.getHandle(), load.getStateBits(),
                           load.getWidth(), load.getBuffer(), Value());
  } else {
    auto bytes = cast<schedule::NativeStateStoreHandleBytesOp>(access);
    createHandleAccessCall(builder, location, entry, bytes.getPlane(),
                           bytes.getHandle(), bytes.getStateBits(),
                           bytes.getWidth(), bytes.getBuffer(),
                           bytes.getChanged());
  }
  access->erase();
}

void lowerNativeStateHandleAccesses(ModuleOp module) {
  SmallVector<Operation *> accesses;
  module.walk([&](Operation *op) {
    if (isNativeStateHandleAccess(op))
      accesses.push_back(op);
  });
  for (Operation *access : accesses)
    lowerNativeStateHandleAccess(access);
}

bool isNativeHandleTransition(Operation *op) {
  return isa<schedule::NativeHandleTransitionOp,
             schedule::NativeHandleTransitionBytesOp>(op);
}

void lowerNativeHandleTransition(Operation *transition,
                                 NativeRuntimeEntry entry,
                                 std::optional<uint32_t> actor) {
  assert(actor.has_value() ==
             (entry != NativeRuntimeEntry::SchedulerSignalTransition) &&
         "only an owned or projected publication names its actor");
  OpBuilder builder(transition);
  Location location = transition->getLoc();
  Type pointer = LLVM::LLVMPointerType::get(builder.getContext());
  SmallVector<Value, 4> temporaries;
  // The runtime reads each plane from memory: a value through a temporary
  // live only around the call. A missing unknown plane is the null pointer:
  // the plane has no X/Z bits.
  auto snapshot = [&](Value plane) -> Value {
    if (!plane)
      return LLVM::ZeroOp::create(builder, location, pointer);
    if (plane.getType() == pointer)
      return plane;
    Value storage =
        detail::beginTemporary(builder, location, plane.getType(), 1);
    LLVM::StoreOp::create(builder, location, plane, storage, 1);
    temporaries.push_back(storage);
    return storage;
  };
  SmallVector<Value, 8> arguments;
  llvm::TypeSwitch<Operation *>(transition)
      .Case<schedule::NativeHandleTransitionOp,
            schedule::NativeHandleTransitionBytesOp>([&](auto transition) {
        arguments.push_back(transition.getRuntimeContext());
        if (actor)
          arguments.push_back(detail::llvmConstant(
              builder, location, builder.getI32Type(), *actor));
        arguments.append({transition.getHandle(),
                          detail::llvmConstant(builder, location,
                                               builder.getI64Type(),
                                               transition.getWidth()),
                          snapshot(transition.getOldValue()),
                          snapshot(transition.getOldUnknown()),
                          snapshot(transition.getNewValue()),
                          snapshot(transition.getNewUnknown())});
      });
  LLVM::CallOp::create(builder, location, TypeRange{},
                       getNativeRuntimeCallee(builder.getContext(), entry),
                       arguments);
  // The runtime consumes the transition before returning.
  for (Value storage : temporaries)
    detail::endTemporary(builder, location, storage);
  transition->erase();
}

void lowerNativeHandleTransitions(ModuleOp module) {
  SmallVector<Operation *> transitions;
  module.walk([&](Operation *op) {
    if (isNativeHandleTransition(op))
      transitions.push_back(op);
  });
  for (Operation *transition : transitions)
    lowerNativeHandleTransition(transition);
}

} // namespace talos
