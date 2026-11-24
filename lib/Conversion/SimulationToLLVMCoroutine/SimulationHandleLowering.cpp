//===- SimulationHandleLowering.cpp - Native handle rewrites ------------===//

#include "SimulationLocalStorageLowering.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"

#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/MapVector.h"

#include <limits>

using namespace mlir;

namespace talos::detail {
namespace {

Value offsetNativeHandle(OpBuilder &builder, Location location, Value handle,
                         Value offset, bool local = false,
                         bool inBounds = false) {
  // A frame handle offsets with plain arithmetic; only its invalid-handle
  // guard is typed.
  if (local) {
    Value invalid =
        llvmConstant(builder, location, builder.getI64Type(), UINT64_MAX);
    Value valid = builder.createOrFold<arith::CmpIOp>(
        location, arith::CmpIPredicate::ne, handle, invalid);
    Value selected =
        builder.createOrFold<arith::AddIOp>(location, handle, offset);
    return builder.createOrFold<schedule::NativeHandleGuardOp>(location, valid,
                                                               selected);
  }
  auto handleConstant = handle.getDefiningOp<arith::ConstantOp>();
  auto offsetConstant = offset.getDefiningOp<arith::ConstantOp>();
  auto handleValue = handleConstant
                         ? dyn_cast<IntegerAttr>(handleConstant.getValue())
                         : IntegerAttr{};
  auto offsetValue = offsetConstant
                         ? dyn_cast<IntegerAttr>(offsetConstant.getValue())
                         : IntegerAttr{};
  // The offset operation does not fold, like the runtime call it stands for:
  // offset constant operands here, as the runtime does.
  if (handleValue && offsetValue) {
    uint64_t folded =
        talos_rt_stable_handle_offset(handleValue.getValue().getZExtValue(),
                                      offsetValue.getValue().getSExtValue());
    return arith::ConstantOp::create(
        builder, location, builder.getI64Type(),
        builder.getI64IntegerAttr(static_cast<int64_t>(folded)));
  }
  // Keep the root/offset form until native access and NBA consumers finish
  // resolving it. The in-bounds proof permits plain encoded addition: the
  // physical root fits in the nonnegative signed 32-bit offset field.
  return schedule::NativeHandleOffsetOp::create(builder, location, handle,
                                                offset, inBounds);
}

Value isValidHandle(OpBuilder &builder, Location location, Value handle) {
  Value invalid = arith::ConstantOp::create(
      builder, location, builder.getI64Type(),
      builder.getI64IntegerAttr(static_cast<int64_t>(UINT64_MAX)));
  return arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                               handle, invalid);
}

template <typename Op>
class ContextHandleConversion final : public OpConversionPattern<Op> {
public:
  ContextHandleConversion(const TypeConverter &converter, MLIRContext *context,
                          const DenseMap<uint64_t, uint64_t> &handles)
      : OpConversionPattern<Op>(converter, context), handles(handles) {}

  LogicalResult
  matchAndRewrite(Op op, typename OpConversionPattern<Op>::OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto found = handles.find(op.getId());
    if (found == handles.end())
      return rewriter.notifyMatchFailure(op, "descriptor has no native layout");
    Value value =
        arith::ConstantOp::create(rewriter, op.getLoc(), rewriter.getI64Type(),
                                  rewriter.getI64IntegerAttr(found->second));
    rewriter.replaceOp(op, value);
    return success();
  }

private:
  const DenseMap<uint64_t, uint64_t> &handles;
};

class EventHandleConversion final
    : public OpConversionPattern<sim::SimContextEventOp> {
public:
  using OpConversionPattern::OpConversionPattern;

  LogicalResult
  matchAndRewrite(sim::SimContextEventOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Value value =
        arith::ConstantOp::create(rewriter, op.getLoc(), rewriter.getI64Type(),
                                  rewriter.getI64IntegerAttr(op.getId()));
    rewriter.replaceOp(op, value);
    return success();
  }
};

template <typename Op>
class HandleViewConversion : public OpConversionPattern<Op> {
public:
  HandleViewConversion(const TypeConverter &converter, MLIRContext *context,
                       const LocalStorageLowering *locals,
                       const DenseSet<Operation *> *inBoundsSelections)
      : OpConversionPattern<Op>(converter, context), locals(locals),
        inBoundsSelections(inBoundsSelections) {}

protected:
  bool isInBounds(Op operation) const {
    return inBoundsSelections && inBoundsSelections->contains(operation);
  }

  SignedI64Index convertIndex(OpBuilder &builder, Location location,
                              Value value, bool inBounds) const {
    if (!inBounds)
      return resizeSignedIndexToI64(builder, location, value);
    unsigned width = cast<IntegerType>(value.getType()).getWidth();
    auto i64 = builder.getI64Type();
    Value index = value;
    if (width < 64)
      index = builder.createOrFold<arith::ExtSIOp>(location, i64, value);
    else if (width > 64)
      index = builder.createOrFold<arith::TruncIOp>(location, i64, value);
    return {index, llvmConstant(builder, location, builder.getI1Type(), 1)};
  }

  bool isLocal(Value reference) const {
    return locals && locals->lookup(reference);
  }

  uint64_t getElementOffset(Value reference, Type type, unsigned index) const {
    return locals->getElementOffset(reference, type, index);
  }
  uint64_t getArrayStride(Value reference) const {
    return locals->getArrayStride(reference);
  }

private:
  const LocalStorageLowering *locals;
  const DenseSet<Operation *> *inBoundsSelections;
};

template <typename Op>
class StaticHandleExtractConversion final : public HandleViewConversion<Op> {
public:
  using HandleViewConversion<Op>::HandleViewConversion;

  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getInput().size() != 1)
      return failure();
    Value offset =
        arith::ConstantOp::create(rewriter, op.getLoc(), rewriter.getI64Type(),
                                  rewriter.getI64IntegerAttr(op.getLowBit()));
    rewriter.replaceOp(op,
                       offsetNativeHandle(rewriter, op.getLoc(),
                                          adaptor.getInput().front(), offset,
                                          this->isLocal(op.getInput())));
    return success();
  }
};

template <typename Op>
class DynamicHandleExtractConversion final : public HandleViewConversion<Op> {
public:
  using HandleViewConversion<Op>::HandleViewConversion;

  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getInput().size() != 1 || adaptor.getLowBit().empty())
      return failure();
    Location location = op.getLoc();
    bool inBounds = this->isInBounds(op);
    SignedI64Index convertedLow = this->convertIndex(
        rewriter, location, adaptor.getLowBit().front(), inBounds);
    Value low = convertedLow.value;
    uint64_t inputWidth =
        *sim::getProvenanceSpan(op.getInput().getType().getElementType());
    unsigned resultWidth =
        *sim::getPackedWidth(op.getResult().getType().getElementType());
    Value valid;
    if (!inBounds) {
      Value minimum = arith::ConstantOp::create(
          rewriter, location, rewriter.getI64Type(),
          rewriter.getI64IntegerAttr(
              std::is_same_v<Op, schedule::NativeWordViewOp>
                  ? 0
                  : -static_cast<int64_t>(resultWidth - 1)));
      Value maximum = arith::ConstantOp::create(
          rewriter, location, rewriter.getI64Type(),
          rewriter.getI64IntegerAttr(
              std::is_same_v<Op, schedule::NativeWordViewOp>
                  ? inputWidth - resultWidth
                  : inputWidth - 1));
      Value overlapsLow = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::sge, low, minimum);
      Value inRange = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::sle, low, maximum);
      valid = arith::AndIOp::create(rewriter, location, overlapsLow, inRange);
      valid = arith::AndIOp::create(rewriter, location, valid,
                                    convertedLow.representable);
      valid = arith::AndIOp::create(
          rewriter, location, valid,
          isValidHandle(rewriter, location, adaptor.getInput().front()));
      if (adaptor.getLowBit().size() == 2) {
        Value known = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::eq,
            adaptor.getLowBit()[1],
            arith::ConstantOp::create(
                rewriter, location, adaptor.getLowBit()[1].getType(),
                rewriter.getZeroAttr(adaptor.getLowBit()[1].getType())));
        valid = arith::AndIOp::create(rewriter, location, valid, known);
      }
    }
    Value selected =
        offsetNativeHandle(rewriter, location, adaptor.getInput().front(), low,
                           this->isLocal(op.getInput()), inBounds);
    if (inBounds) {
      rewriter.replaceOp(op, selected);
      return success();
    }
    rewriter.replaceOp(op, schedule::NativeHandleGuardOp::create(
                               rewriter, location, valid, selected));
    return success();
  }
};

template <typename Op>
class SubelementHandleConversion final : public HandleViewConversion<Op> {
public:
  using HandleViewConversion<Op>::HandleViewConversion;

  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getInput().size() != 1)
      return failure();
    Type current = op.getInput().getType().getElementType();
    uint64_t offset = 0;
    for (int64_t rawIndex : op.getIndices()) {
      if (rawIndex < 0 || static_cast<uint64_t>(rawIndex) >=
                              sim::getAggregateNumElements(current))
        return failure();
      unsigned index = static_cast<unsigned>(rawIndex);
      auto subelement = sim::getAggregateProvenanceSubelement(current, index);
      if (!subelement ||
          subelement->first > std::numeric_limits<uint64_t>::max() - offset)
        return failure();
      offset += this->isLocal(op.getInput())
                    ? this->getElementOffset(op.getInput(), current, index)
                    : subelement->first;
      current = sim::getAggregateElementType(current, index);
    }
    Value amount =
        arith::ConstantOp::create(rewriter, op.getLoc(), rewriter.getI64Type(),
                                  rewriter.getI64IntegerAttr(offset));
    rewriter.replaceOp(op,
                       offsetNativeHandle(rewriter, op.getLoc(),
                                          adaptor.getInput().front(), amount,
                                          this->isLocal(op.getInput())));
    return success();
  }
};

template <typename Op>
class ArrayElementHandleConversion final : public HandleViewConversion<Op> {
public:
  using HandleViewConversion<Op>::HandleViewConversion;

  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getInput().size() != 1 || adaptor.getIndex().empty())
      return failure();
    Type array = op.getInput().getType().getElementType();
    int64_t left;
    int64_t right;
    bool packed;
    Type element;
    if (auto type = dyn_cast<sim::PackedArrayType>(array)) {
      left = type.getLeft();
      right = type.getRight();
      packed = true;
      element = type.getElementType();
    } else if (auto type = dyn_cast<sim::UnpackedArrayType>(array)) {
      left = type.getLeft();
      right = type.getRight();
      packed = false;
      element = type.getElementType();
    } else {
      return failure();
    }
    std::optional<uint64_t> span = sim::getArrayElementStorageStride(array);
    uint64_t count = sim::getAggregateNumElements(array);
    if (this->isLocal(op.getInput()))
      span = this->getArrayStride(op.getInput());
    if (!span || count == 0)
      return failure();

    Location location = op.getLoc();
    IntegerType i64 = rewriter.getI64Type();
    bool inBounds = this->isInBounds(op);
    SignedI64Index convertedIndex = this->convertIndex(
        rewriter, location, adaptor.getIndex().front(), inBounds);
    Value index = convertedIndex.value;
    Value leftValue = arith::ConstantOp::create(
        rewriter, location, i64, rewriter.getI64IntegerAttr(left));
    Value rightValue = arith::ConstantOp::create(
        rewriter, location, i64, rewriter.getI64IntegerAttr(right));
    Value valid;
    Value ordinal;
    if (left >= right) {
      if (!inBounds) {
        Value atMostLeft = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::sle, index, leftValue);
        Value atLeastRight = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::sge, index, rightValue);
        valid =
            arith::AndIOp::create(rewriter, location, atMostLeft, atLeastRight);
      }
      ordinal =
          rewriter.createOrFold<arith::SubIOp>(location, leftValue, index);
    } else {
      if (!inBounds) {
        Value atLeastLeft = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::sge, index, leftValue);
        Value atMostRight = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::sle, index, rightValue);
        valid =
            arith::AndIOp::create(rewriter, location, atLeastLeft, atMostRight);
      }
      ordinal =
          rewriter.createOrFold<arith::SubIOp>(location, index, leftValue);
    }
    if (!inBounds) {
      valid = arith::AndIOp::create(rewriter, location, valid,
                                    convertedIndex.representable);
      if (adaptor.getIndex().size() == 2) {
        Value known = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::eq, adaptor.getIndex()[1],
            arith::ConstantOp::create(
                rewriter, location, adaptor.getIndex()[1].getType(),
                rewriter.getZeroAttr(adaptor.getIndex()[1].getType())));
        valid = arith::AndIOp::create(rewriter, location, valid, known);
      }
      valid = arith::AndIOp::create(
          rewriter, location, valid,
          isValidHandle(rewriter, location, adaptor.getInput().front()));
    }
    if (packed) {
      Value last = arith::ConstantOp::create(
          rewriter, location, i64,
          rewriter.getI64IntegerAttr(static_cast<int64_t>(count - 1)));
      ordinal = arith::SubIOp::create(rewriter, location, last, ordinal);
    }
    Value stride = arith::ConstantOp::create(rewriter, location, i64,
                                             rewriter.getI64IntegerAttr(*span));
    Value offset = arith::MulIOp::create(rewriter, location, ordinal, stride);
    Value selected =
        offsetNativeHandle(rewriter, location, adaptor.getInput().front(),
                           offset, this->isLocal(op.getInput()), inBounds);
    if (inBounds) {
      rewriter.replaceOp(op, selected);
      return success();
    }
    rewriter.replaceOp(op, schedule::NativeHandleGuardOp::create(
                               rewriter, location, valid, selected));
    return success();
  }
};

} // namespace

void populateNativeHandleConversionPatterns(
    RewritePatternSet &patterns, TypeConverter &converter,
    const DenseMap<uint64_t, uint64_t> &storageHandles,
    const DenseMap<uint64_t, uint64_t> &netHandles,
    const DenseMap<uint64_t, uint64_t> &driverHandles,
    const LocalStorageLowering *locals,
    const DenseSet<Operation *> *inBoundsSelections) {
  MLIRContext *context = patterns.getContext();
  patterns.add<ContextHandleConversion<sim::SimContextStorageOp>>(
      converter, context, storageHandles);
  patterns.add<ContextHandleConversion<sim::SimContextNetOp>>(
      converter, context, netHandles);
  patterns.add<ContextHandleConversion<sim::SimContextDriverOp>>(
      converter, context, driverHandles);
  patterns.add<EventHandleConversion>(converter, context);
  patterns.add<StaticHandleExtractConversion<sim::SimRefExtractOp>,
               StaticHandleExtractConversion<sim::SimNetExtractOp>,
               StaticHandleExtractConversion<sim::SimDriverExtractOp>,
               DynamicHandleExtractConversion<sim::SimRefDynExtractOp>,
               DynamicHandleExtractConversion<schedule::NativeWordViewOp>,
               DynamicHandleExtractConversion<sim::SimDriverDynExtractOp>,
               SubelementHandleConversion<sim::SimRefSubelementOp>,
               SubelementHandleConversion<sim::SimDriverSubelementOp>,
               ArrayElementHandleConversion<sim::SimRefArrayElementOp>,
               ArrayElementHandleConversion<sim::SimDriverArrayElementOp>>(
      converter, context, locals, inBoundsSelections);
}

} // namespace talos::detail

namespace talos {
namespace {
SmallVector<Operation *> collectNativeHandleOps(ModuleOp module) {
  SmallVector<Operation *> handles;
  module.walk([&](Operation *op) {
    if (isa<schedule::NativeHandleOffsetOp, schedule::NativeHandleGuardOp>(op))
      handles.push_back(op);
  });
  return handles;
}

// Handle operations read and write no state (a total function whose invalid
// selection is the invalid handle, IEEE 1800-2023 7.4.5, 11.5.1), and AOT
// planning has read every selection by now. An offset recomputing one that
// dominates it takes that one's handle, whether or not either is proved in
// bounds: equal operands give an equal handle. A dominating offset proved in
// bounds ran on those operands, so they satisfy its proof: being not
// speculatable, it has not moved above the guards its proof depends on.
// Folding then drops offsets by zero, merges offsets proved in bounds and
// erases handle operations nothing uses, so none of those reaches the
// runtime.
void simplifyNativeHandleOps(ModuleOp module, ArrayRef<Operation *> handles) {
  llvm::MapVector<std::pair<Value, Value>,
                  SmallVector<schedule::NativeHandleOffsetOp, 2>>
      offsets;
  for (Operation *op : handles)
    if (auto offset = dyn_cast<schedule::NativeHandleOffsetOp>(op))
      offsets[{offset.getHandle(), offset.getAmount()}].push_back(offset);
  DominanceInfo dominance(module);
  for (auto &[key, equal] : offsets) {
    if (equal.size() < 2)
      continue;
    // The offsets dominating one form a chain; its first is not dominated by
    // any other of them.
    SmallVector<schedule::NativeHandleOffsetOp, 2> first;
    for (schedule::NativeHandleOffsetOp offset : equal)
      if (llvm::none_of(equal, [&](schedule::NativeHandleOffsetOp other) {
            return dominance.properlyDominates(other.getOperation(),
                                               offset.getOperation());
          }))
        first.push_back(offset);
    for (schedule::NativeHandleOffsetOp offset : equal) {
      if (llvm::is_contained(first, offset))
        continue;
      // In a graph region the offsets of one block dominate each other, so
      // none of them is first and each stays.
      auto dominating =
          llvm::find_if(first, [&](schedule::NativeHandleOffsetOp other) {
            return dominance.properlyDominates(other.getOperation(),
                                               offset.getOperation());
          });
      if (dominating == first.end())
        continue;
      offset.replaceAllUsesWith(dominating->getResult());
      offset.erase();
    }
  }
  SmallVector<Operation *> remaining = collectNativeHandleOps(module);
  if (remaining.empty())
    return;
  RewritePatternSet patterns(module.getContext());
  schedule::NativeHandleOffsetOp::getCanonicalizationPatterns(
      patterns, module.getContext());
  GreedyRewriteConfig config;
  config.setStrictness(GreedyRewriteStrictness::ExistingAndNewOps)
      .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled)
      .enableConstantCSE(false);
  (void)applyOpPatternsGreedily(remaining, std::move(patterns), config);
}
} // namespace

void lowerNativeHandleOps(ModuleOp module) {
  SmallVector<Operation *> handles = collectNativeHandleOps(module);
  if (handles.empty())
    return;
  simplifyNativeHandleOps(module, handles);
  handles = collectNativeHandleOps(module);
  DenseMap<Value, uint64_t> taggedObjects;
  for (Operation *op : handles) {
    OpBuilder builder(op);
    Location location = op->getLoc();
    Type i64 = builder.getI64Type();
    Value lowered;
    Value source = isa<schedule::NativeHandleOffsetOp>(op)
                       ? cast<schedule::NativeHandleOffsetOp>(op).getHandle()
                       : cast<schedule::NativeHandleGuardOp>(op).getHandle();
    std::optional<uint64_t> object;
    if (auto it = taggedObjects.find(source); it != taggedObjects.end()) {
      object = it->second;
    } else if (auto bits = detail::resolveCFGConstantInteger(source)) {
      talos_rt_stable_handle_v1 decoded;
      if (talos_rt_stable_handle_decode(*bits, &decoded) &&
          decoded.kind != TALOS_RT_STABLE_HANDLE_GLOBAL)
        object = talos_rt_stable_handle_encode(decoded.kind, decoded.id, 0);
    }
    if (auto offset = dyn_cast<schedule::NativeHandleOffsetOp>(op)) {
      // An offset proved in bounds neither carries nor borrows in the offset
      // field, so the runtime's result is the plain sum.
      if (offset.getInBounds())
        lowered = LLVM::AddOp::create(builder, location, offset.getHandle(),
                                      offset.getAmount());
      else if (object) {
        // A field of this object has a signed 32-bit offset. Offsetting an
        // invalid selection stays invalid, including when the displacement
        // would otherwise bring it back inside the object (11.5.1).
        Type i32 = builder.getI32Type();
        Value invalid =
            detail::llvmConstant(builder, location, i64, UINT64_MAX);
        Value prior = LLVM::TruncOp::create(builder, location, i32, source);
        // Even an overflowing i64 sum wraps to within 2^31 of an i64
        // extreme, outside the signed 32-bit range tested below.
        Value sum = LLVM::AddOp::create(
            builder, location,
            LLVM::SExtOp::create(builder, location, i64, prior),
            offset.getAmount());
        Value field = LLVM::TruncOp::create(builder, location, i32, sum);
        Value fits = arith::CmpIOp::create(
            builder, location, arith::CmpIPredicate::eq, sum,
            LLVM::SExtOp::create(builder, location, i64, field));
        Value valid = arith::AndIOp::create(
            builder, location, fits,
            arith::CmpIOp::create(builder, location, arith::CmpIPredicate::ne,
                                  source, invalid));
        Value tagged = arith::OrIOp::create(
            builder, location,
            detail::llvmConstant(builder, location, i64, *object),
            LLVM::ZExtOp::create(builder, location, i64, field));
        lowered =
            arith::SelectOp::create(builder, location, valid, tagged, invalid);
      } else
        lowered =
            LLVM::CallOp::create(
                builder, location, TypeRange{i64},
                getNativeRuntimeCallee(builder.getContext(),
                                       NativeRuntimeEntry::NativeHandleOffset),
                ValueRange{offset.getHandle(), offset.getAmount()})
                .getResult();
    } else {
      auto guard = cast<schedule::NativeHandleGuardOp>(op);
      // A frame handle's validity compares the handle with an invalid-handle
      // constant; the select takes that same constant.
      Value invalid;
      APInt constant;
      if (auto compare = guard.getValid().getDefiningOp<arith::CmpIOp>();
          compare && compare.getPredicate() == arith::CmpIPredicate::ne &&
          matchPattern(compare.getRhs(), m_ConstantInt(&constant)) &&
          constant.getBitWidth() == 64 && constant.isAllOnes())
        invalid = compare.getRhs();
      else
        invalid = arith::ConstantOp::create(
            builder, location, i64,
            builder.getI64IntegerAttr(static_cast<int64_t>(UINT64_MAX)));
      lowered = arith::SelectOp::create(builder, location, guard.getValid(),
                                        guard.getHandle(), invalid);
    }
    if (object)
      taggedObjects.try_emplace(lowered, *object);
    op->getResult(0).replaceAllUsesWith(lowered);
    op->erase();
  }
}
} // namespace talos
