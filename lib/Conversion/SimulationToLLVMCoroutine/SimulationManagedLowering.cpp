//===- SimulationManagedLowering.cpp - Managed runtime lowering -------===//

#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "talos/Analysis/SimulationStorageAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>

using namespace mlir;

namespace talos::detail {

Value managedObjectPointer(OpBuilder &builder, Location location,
                           Value handle) {
  return LLVM::IntToPtrOp::create(
      builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
      handle);
}

Value managedObjectHandle(OpBuilder &builder, Location location, Value object) {
  return LLVM::PtrToIntOp::create(builder, location, builder.getI64Type(),
                                  object);
}

Value managedContext(OpBuilder &builder, Location location) {
  Type pointer = LLVM::LLVMPointerType::get(builder.getContext());
  Value address = LLVM::AddressOfOp::create(builder, location, pointer,
                                            "__talos_current_context");
  return LLVM::LoadOp::create(builder, location, pointer, address, 8);
}

std::pair<Value, Value> managedContextAndLane(OpBuilder &builder,
                                              Location location) {
  Type pointer = LLVM::LLVMPointerType::get(builder.getContext());
  Value context = managedContext(builder, location);
  Value lane =
      LLVM::CallOp::create(builder, location, TypeRange{pointer},
                           SymbolRefAttr::get(builder.getContext(),
                                              "talos_rt_v1_gc_current_lane"),
                           context)
          .getResult();
  return {context, lane};
}

Operation *reportManagedStatus(OpBuilder &builder, Location location,
                               Value context, Value status) {
  (void)context;
  Type statusType = runtime::StatusType::get(builder.getContext());
  Value runtimeStatus = runtime::RTStatusFromBitsOp::create(builder, location,
                                                            statusType, status);
  return sim::SimStatusCheckOp::create(builder, location, runtimeStatus);
}

namespace {

class ClassNullConversion final
    : public OpConversionPattern<sim::SimClassNullOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassNullOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, arith::ConstantOp::create(
                               rewriter, op.getLoc(), rewriter.getI64Type(),
                               rewriter.getI64IntegerAttr(0)));
    return success();
  }
};

class ManagedNullConversion final
    : public OpConversionPattern<sim::SimManagedNullOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimManagedNullOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, arith::ConstantOp::create(
                               rewriter, op.getLoc(), rewriter.getI64Type(),
                               rewriter.getI64IntegerAttr(0)));
    return success();
  }
};

template <typename Op>
class ManagedIdentityEqualConversion final : public OpConversionPattern<Op> {
public:
  using OpConversionPattern<Op>::OpConversionPattern;
  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getLhs().size() != 1 || adaptor.getRhs().size() != 1)
      return failure();
    rewriter.replaceOpWithNewOp<arith::CmpIOp>(op, arith::CmpIPredicate::eq,
                                               adaptor.getLhs().front(),
                                               adaptor.getRhs().front());
    return success();
  }
};

class ManagedWatchNullConversion final
    : public OpConversionPattern<sim::SimManagedWatchNullOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimManagedWatchNullOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, arith::ConstantOp::create(
                               rewriter, op.getLoc(), rewriter.getI64Type(),
                               rewriter.getI64IntegerAttr(0)));
    return success();
  }
};

class ManagedIsNullConversion final
    : public OpConversionPattern<sim::SimManagedIsNullOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimManagedIsNullOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getInput().size() != 1)
      return failure();
    Value zero = llvmConstant(rewriter, op.getLoc(),
                              adaptor.getInput().front().getType(), 0);
    rewriter.replaceOpWithNewOp<arith::CmpIOp>(
        op, arith::CmpIPredicate::eq, adaptor.getInput().front(), zero);
    return success();
  }
};

class EventNullConversion final
    : public OpConversionPattern<sim::SimEventNullOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimEventNullOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, arith::ConstantOp::create(
                               rewriter, op.getLoc(), rewriter.getI64Type(),
                               rewriter.getI64IntegerAttr(-1)));
    return success();
  }
};

class ClassAllocConversion final
    : public OpConversionPattern<sim::SimClassAllocOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassAllocOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    auto classType = cast<sim::ClassHandleType>(op.getResult().getType());
    Value descriptor = LLVM::AddressOfOp::create(
        rewriter, op.getLoc(), pointer,
        managedClassDescriptorName(classType.getClassName()));
    Value output = entryAlloca(rewriter, op.getLoc(), pointer, 1, 8);
    LLVM::StoreOp::create(rewriter, op.getLoc(),
                          LLVM::ZeroOp::create(rewriter, op.getLoc(), pointer),
                          output, 8);
    Value status = LLVM::CallOp::create(
                       rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
                       SymbolRefAttr::get(rewriter.getContext(),
                                          "talos_rt_v1_object_allocate"),
                       ValueRange{lane, descriptor, output})
                       .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    Value object =
        LLVM::LoadOp::create(rewriter, op.getLoc(), pointer, output, 8);
    rewriter.replaceOp(op, managedObjectHandle(rewriter, op.getLoc(), object));
    return success();
  }
};

class ClassCopyConversion final
    : public OpConversionPattern<sim::SimClassCopyOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassCopyOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getSource().size() != 1)
      return failure();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    auto classType = cast<sim::ClassHandleType>(op.getResult().getType());
    Value descriptor = LLVM::AddressOfOp::create(
        rewriter, op.getLoc(), pointer,
        managedClassDescriptorName(classType.getClassName()));
    Value output = entryAlloca(rewriter, op.getLoc(), pointer, 1, 8);
    LLVM::StoreOp::create(rewriter, op.getLoc(),
                          LLVM::ZeroOp::create(rewriter, op.getLoc(), pointer),
                          output, 8);
    Value source = managedObjectPointer(rewriter, op.getLoc(),
                                        adaptor.getSource().front());
    Value status = LLVM::CallOp::create(
                       rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
                       SymbolRefAttr::get(rewriter.getContext(),
                                          "talos_rt_v1_object_shallow_copy"),
                       ValueRange{lane, descriptor, source, output})
                       .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    Value object =
        LLVM::LoadOp::create(rewriter, op.getLoc(), pointer, output, 8);
    rewriter.replaceOp(op, managedObjectHandle(rewriter, op.getLoc(), object));
    return success();
  }
};

class ClassBuiltinUpcastConversion final
    : public OpConversionPattern<sim::SimClassBuiltinUpcastOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassBuiltinUpcastOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getObject().size() != 1)
      return failure();
    rewriter.replaceOp(op, adaptor.getObject());
    return success();
  }
};

class ClassIsInstanceConversion final
    : public OpConversionPattern<sim::SimClassIsInstanceOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassIsInstanceOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getObject().size() != 1)
      return failure();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Value object = managedObjectPointer(rewriter, op.getLoc(),
                                        adaptor.getObject().front());
    Value descriptor = LLVM::AddressOfOp::create(
        rewriter, op.getLoc(), pointer,
        managedClassDescriptorName(op.getTargetAttr()));
    Value result = LLVM::CallOp::create(
                       rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
                       SymbolRefAttr::get(rewriter.getContext(),
                                          "talos_rt_v1_object_is_instance"),
                       ValueRange{object, descriptor})
                       .getResult();
    rewriter.replaceOp(op, LLVM::TruncOp::create(rewriter, op.getLoc(),
                                                 rewriter.getI1Type(), result));
    return success();
  }
};

class ClassIdConversion final : public OpConversionPattern<sim::SimClassIdOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassIdOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getObject().size() != 1)
      return failure();
    Value object = managedObjectPointer(rewriter, op.getLoc(),
                                        adaptor.getObject().front());
    rewriter.replaceOp(
        op,
        LLVM::CallOp::create(
            rewriter, op.getLoc(), TypeRange{rewriter.getI64Type()},
            SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_object_id"),
            object)
            .getResults());
    return success();
  }
};

class ClassCastConversion final
    : public OpConversionPattern<sim::SimClassCastOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassCastOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getObject().size() != 1)
      return failure();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    (void)lane;
    auto targetType = cast<sim::ClassHandleType>(op.getResult().getType());
    Value descriptor = LLVM::AddressOfOp::create(
        rewriter, op.getLoc(), pointer,
        managedClassDescriptorName(targetType.getClassName()));
    Value output = entryAlloca(rewriter, op.getLoc(), pointer, 1, 8);
    Value status =
        LLVM::CallOp::create(
            rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_object_cast"),
            ValueRange{managedObjectPointer(rewriter, op.getLoc(),
                                            adaptor.getObject().front()),
                       descriptor, output})
            .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    Value result =
        LLVM::LoadOp::create(rewriter, op.getLoc(), pointer, output, 8);
    rewriter.replaceOp(op, managedObjectHandle(rewriter, op.getLoc(), result));
    return success();
  }
};

class ClassFieldRefConversion final
    : public OpConversionPattern<sim::SimClassFieldRefOp> {
public:
  ClassFieldRefConversion(const TypeConverter &converter, MLIRContext *context,
                          const NativeClassLowering &classes)
      : OpConversionPattern(converter, context), classes(classes) {}
  LogicalResult
  matchAndRewrite(sim::SimClassFieldRefOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getObject().size() != 1)
      return failure();
    auto field = classes.fieldOffsets.find(op);
    if (field == classes.fieldOffsets.end())
      return op.emitError("managed class field has no native offset");
    SmallVector<Value> values{
        adaptor.getObject().front(),
        arith::ConstantOp::create(rewriter, op.getLoc(), rewriter.getI64Type(),
                                  rewriter.getI64IntegerAttr(field->second))};
    SmallVector<ValueRange> replacements{ValueRange(values)};
    rewriter.replaceOpWithMultiple(op, replacements);
    return success();
  }

private:
  const NativeClassLowering &classes;
};

class ManagedWatchConversion final
    : public OpConversionPattern<sim::SimManagedWatchOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimManagedWatchOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    ValueRange input = adaptor.getInput();
    Value object;
    Value selector;
    std::optional<uint32_t> runtimeKind;
    switch (op.getKind()) {
    case sim::ManagedWatchKind::Field:
      if (input.size() != 2)
        return failure();
      object = input[0];
      selector = input[1];
      runtimeKind = TALOS_RT_MANAGED_WATCH_FIELD;
      break;
    case sim::ManagedWatchKind::ContainerSize:
      if (input.size() != 1)
        return failure();
      object = input[0];
      selector = llvmConstant(rewriter, op.getLoc(), rewriter.getI64Type(), 0);
      runtimeKind = TALOS_RT_MANAGED_WATCH_CONTAINER_SIZE;
      break;
    }
    if (!runtimeKind)
      return rewriter.notifyMatchFailure(op, "unknown managed-watch kind");
    Value kind = llvmConstant(rewriter, op.getLoc(), rewriter.getI32Type(),
                              *runtimeKind);
    rewriter.replaceOp(
        op, LLVM::CallOp::create(
                rewriter, op.getLoc(), TypeRange{rewriter.getI64Type()},
                SymbolRefAttr::get(rewriter.getContext(),
                                   "talos_rt_v1_managed_watch"),
                ValueRange{managedObjectPointer(rewriter, op.getLoc(), object),
                           kind, selector})
                .getResults());
    return success();
  }
};

class ClassRootBindConversion final
    : public OpConversionPattern<sim::SimClassRootBindOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimClassRootBindOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if ((adaptor.getObject().size() != 1 && adaptor.getObject().size() != 2) ||
        adaptor.getSlot().size() != 1)
      return failure();
    Value owner = adaptor.getObject().front();
    Type sourceType = op.getObject().getType();
    uint64_t bitOffset = op.getBitOffset();
    if (isa<sim::ArgumentRefType>(sourceType)) {
      owner = arith::TruncIOp::create(rewriter, op.getLoc(),
                                      rewriter.getI64Type(), owner);
    } else if (!isa<sim::ManagedRefType>(sourceType)) {
      auto integer = dyn_cast<IntegerType>(owner.getType());
      if (!integer || integer.getWidth() < 64 ||
          bitOffset > integer.getWidth() - 64)
        return failure();
      if (bitOffset != 0)
        owner = arith::ShRUIOp::create(
            rewriter, op.getLoc(), owner,
            llvmConstant(rewriter, op.getLoc(), integer, bitOffset));
      if (integer.getWidth() != 64)
        owner = arith::TruncIOp::create(rewriter, op.getLoc(),
                                        rewriter.getI64Type(), owner);
    }
    if (op.getMode() == sim::ManagedRootMode::Candidate) {
      Value contextAddress = LLVM::AddressOfOp::create(
          rewriter, op.getLoc(),
          LLVM::LLVMPointerType::get(rewriter.getContext()),
          "__talos_current_context");
      Value context = LLVM::LoadOp::create(
          rewriter, op.getLoc(),
          LLVM::LLVMPointerType::get(rewriter.getContext()), contextAddress, 8);
      owner =
          LLVM::CallOp::create(
              rewriter, op.getLoc(), TypeRange{rewriter.getI64Type()},
              SymbolRefAttr::get(rewriter.getContext(),
                                 "talos_rt_v1_gc_candidate_root"),
              ValueRange{context, owner,
                         llvmConstant(rewriter, op.getLoc(),
                                      rewriter.getI32Type(), op.getKindMask())})
              .getResult();
    }
    LLVM::StoreOp::create(rewriter, op.getLoc(), owner,
                          adaptor.getSlot().front(), 8);
    rewriter.eraseOp(op);
    return success();
  }
};

template <typename Op>
class ManagedObjectOutputConversion final : public OpConversionPattern<Op> {
public:
  using OpConversionPattern<Op>::OpConversionPattern;
  LogicalResult
  matchAndRewrite(Op op,
                  typename OpConversionPattern<Op>::OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    ValueRange input;
    if constexpr (std::is_same_v<Op, sim::SimWeakCreateOp>)
      input = adaptor.getReferent();
    else
      input = adaptor.getWeak();
    if (input.size() != 1)
      return failure();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    Value output = entryAlloca(rewriter, op.getLoc(), pointer, 1, 8);
    LLVM::StoreOp::create(rewriter, op.getLoc(),
                          LLVM::ZeroOp::create(rewriter, op.getLoc(), pointer),
                          output, 8);
    SmallVector<Value> arguments;
    if constexpr (std::is_same_v<Op, sim::SimWeakCreateOp>) {
      arguments.push_back(lane);
      auto wrapperType = cast<sim::ClassHandleType>(op.getResult().getType());
      arguments.push_back(LLVM::AddressOfOp::create(
          rewriter, op.getLoc(), pointer,
          managedClassDescriptorName(wrapperType.getClassName())));
    }
    arguments.push_back(
        managedObjectPointer(rewriter, op.getLoc(), input.front()));
    arguments.push_back(output);
    Value status =
        LLVM::CallOp::create(
            rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
            SymbolRefAttr::get(rewriter.getContext(),
                               std::is_same_v<Op, sim::SimWeakCreateOp>
                                   ? "talos_rt_v1_weak_create"
                                   : "talos_rt_v1_weak_get"),
            arguments)
            .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    Value object =
        LLVM::LoadOp::create(rewriter, op.getLoc(), pointer, output, 8);
    rewriter.replaceOp(op, managedObjectHandle(rewriter, op.getLoc(), object));
    return success();
  }
};

class WeakClearConversion final
    : public OpConversionPattern<sim::SimWeakClearOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimWeakClearOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getWeak().size() != 1)
      return failure();
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    (void)lane;
    Value status =
        LLVM::CallOp::create(
            rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
            SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_weak_clear"),
            managedObjectPointer(rewriter, op.getLoc(),
                                 adaptor.getWeak().front()))
            .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    rewriter.eraseOp(op);
    return success();
  }
};

class GCSafepointConversion final
    : public OpConversionPattern<sim::SimGCSafepointOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimGCSafepointOp op, OneToNOpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    Value status = LLVM::CallOp::create(
                       rewriter, op.getLoc(), TypeRange{rewriter.getI32Type()},
                       SymbolRefAttr::get(rewriter.getContext(),
                                          "talos_rt_v1_gc_safepoint"),
                       lane)
                       .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    rewriter.eraseOp(op);
    return success();
  }
};

class ClassVirtualCallConversion final
    : public OpConversionPattern<sim::SimClassVirtualCallOp> {
public:
  ClassVirtualCallConversion(const TypeConverter &converter,
                             MLIRContext *context,
                             const llvm::DataLayout &dataLayout,
                             const NativeClassLowering &classes)
      : OpConversionPattern(converter, context), dataLayout(dataLayout),
        classes(classes) {}

  LogicalResult
  matchAndRewrite(sim::SimClassVirtualCallOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getReceiver().size() != 1 ||
        adaptor.getArguments().size() != op.getArguments().size())
      return failure();
    auto dispatch = classes.dispatches.find(op);
    if (dispatch == classes.dispatches.end())
      return op.emitError("virtual method descriptor is missing");
    if (dispatch->second.vtablePath)
      return lowerTypedCall(op, adaptor, rewriter,
                            *dispatch->second.vtablePath);
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Type argumentType =
        LLVM::LLVMStructType::getLiteral(rewriter.getContext(), {pointer, i64});
    SmallVector<std::pair<Value, uint64_t>> physicalArguments;
    llvm::DataLayout local(dataLayout.getStringRepresentation());
    llvm::LLVMContext llvmContext;
    for (auto [original, converted] :
         llvm::zip_equal(op.getArguments(), adaptor.getArguments())) {
      FailureOr<analysis::SimulationStorageProperties> storage =
          analysis::getSimulationStorageProperties(original.getType(), local,
                                                   llvmContext);
      if (failed(storage) ||
          converted.size() !=
              analysis::getSimulationPhysicalStorageCount(*storage))
        return failure();
      for (Value value : converted)
        physicalArguments.push_back({value, storage->size});
    }

    Value argumentArray = LLVM::ZeroOp::create(rewriter, op.getLoc(), pointer);
    if (!physicalArguments.empty()) {
      argumentArray = entryAlloca(rewriter, op.getLoc(), argumentType,
                                  physicalArguments.size(), 8);
      for (auto [index, argument] : llvm::enumerate(physicalArguments)) {
        Value data =
            entryAlloca(rewriter, op.getLoc(), argument.first.getType(), 1, 8);
        LLVM::StoreOp::create(rewriter, op.getLoc(), argument.first, data, 1);
        Value record =
            LLVM::ZeroOp::create(rewriter, op.getLoc(), argumentType);
        record = insertValue(rewriter, op.getLoc(), record, data, 0);
        record = insertValue(
            rewriter, op.getLoc(), record,
            llvmConstant(rewriter, op.getLoc(), i64, argument.second), 1);
        LLVM::StoreOp::create(
            rewriter, op.getLoc(), record,
            byteGEP(rewriter, op.getLoc(), argumentArray, index * 16), 8);
      }
    }

    SmallVector<Type> convertedResults;
    SmallVector<uint64_t> resultOffsets;
    uint64_t resultSize = 0;
    uint32_t resultAlignment = 1;
    for (Type original : op.getResultTypes()) {
      FailureOr<analysis::SimulationStorageProperties> storage =
          analysis::getSimulationStorageProperties(original, local,
                                                   llvmContext);
      SmallVector<Type> converted;
      if (failed(storage) ||
          failed(getTypeConverter()->convertType(original, converted)) ||
          converted.size() !=
              analysis::getSimulationPhysicalStorageCount(*storage))
        return failure();
      for (Type type : converted) {
        uint64_t offset;
        if (!alignUp(resultSize, storage->alignment, offset) ||
            storage->size > std::numeric_limits<uint64_t>::max() - offset)
          return op.emitError("managed method result layout overflow");
        resultOffsets.push_back(offset);
        resultSize = offset + storage->size;
        resultAlignment =
            std::max<uint32_t>(resultAlignment, storage->alignment);
        convertedResults.push_back(type);
      }
    }
    if (!alignUp(resultSize, resultAlignment, resultSize))
      return op.emitError("managed method result layout overflow");
    Value resultStorage = LLVM::ZeroOp::create(rewriter, op.getLoc(), pointer);
    if (resultSize != 0)
      resultStorage = entryAlloca(rewriter, op.getLoc(), rewriter.getI8Type(),
                                  resultSize, resultAlignment);

    auto [context, lane] = managedContextAndLane(rewriter, op.getLoc());
    SmallVector<Value> invokeArguments{
        lane, managedObjectPointer(rewriter, op.getLoc(),
                                   adaptor.getReceiver().front())};
    StringRef invokeName = "talos_rt_v1_method_invoke";
    const auto &target = dispatch->second;
    if (target.isInterface) {
      invokeName = "talos_rt_v1_interface_method_invoke";
      invokeArguments.push_back(
          llvmConstant(rewriter, op.getLoc(), i64, target.ownerID));
      invokeArguments.push_back(
          llvmConstant(rewriter, op.getLoc(), i64, target.interfaceOrdinal));
    } else {
      invokeArguments.push_back(
          llvmConstant(rewriter, op.getLoc(), i64, op.getSlot()));
    }
    invokeArguments.push_back(
        llvmConstant(rewriter, op.getLoc(), i64, op.getSignatureId()));
    invokeArguments.push_back(argumentArray);
    invokeArguments.push_back(
        llvmConstant(rewriter, op.getLoc(), i32, physicalArguments.size()));
    invokeArguments.push_back(resultStorage);
    invokeArguments.push_back(
        llvmConstant(rewriter, op.getLoc(), i64, resultSize));
    Value status = LLVM::CallOp::create(
                       rewriter, op.getLoc(), TypeRange{i32},
                       SymbolRefAttr::get(rewriter.getContext(), invokeName),
                       invokeArguments)
                       .getResult();
    reportManagedStatus(rewriter, op.getLoc(), context, status);
    SmallVector<Value> results;
    for (auto [type, offset] : llvm::zip_equal(convertedResults, resultOffsets))
      results.push_back(LLVM::LoadOp::create(
          rewriter, op.getLoc(), type,
          byteGEP(rewriter, op.getLoc(), resultStorage, offset), 1));

    SmallVector<SmallVector<Value>> replacements;
    size_t physical = 0;
    for (Type original : op.getResultTypes()) {
      SmallVector<Type> converted;
      if (failed(getTypeConverter()->convertType(original, converted)))
        return failure();
      replacements.emplace_back(results.begin() + physical,
                                results.begin() + physical + converted.size());
      physical += converted.size();
    }
    rewriter.replaceOpWithMultiple(op, std::move(replacements));
    return success();
  }

private:
  LogicalResult lowerTypedCall(sim::SimClassVirtualCallOp op,
                               OneToNOpAdaptor adaptor,
                               ConversionPatternRewriter &rewriter,
                               std::pair<uint32_t, uint32_t> path) const {
    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    SmallVector<Type> resultTypes;
    SmallVector<unsigned> resultCounts;
    for (Type type : op.getResultTypes()) {
      SmallVector<Type> converted;
      if (failed(getTypeConverter()->convertType(type, converted)))
        return failure();
      resultCounts.push_back(converted.size());
      llvm::append_range(resultTypes, converted);
    }
    SmallVector<Type> entryResults(resultTypes);
    entryResults.push_back(i32);
    Type entryResultType = entryResults.size() == 1
                               ? i32
                               : LLVM::LLVMStructType::getLiteral(
                                     rewriter.getContext(), entryResults);
    Value context = managedContext(rewriter, location);
    Value receiver = adaptor.getReceiver().front();
    Value object = managedObjectPointer(rewriter, location, receiver);
    Block *head = op->getBlock();
    Block *continuation = rewriter.splitBlock(head, op->getIterator());
    SmallVector<Value> merged;
    for (Type type : resultTypes)
      merged.push_back(continuation->addArgument(type, location));
    auto block = [&]() {
      OpBuilder::InsertionGuard guard(rewriter);
      return rewriter.createBlock(continuation);
    };
    Block *lookup = block();
    Block *nullReceiver = block();
    Block *missing = block();
    rewriter.setInsertionPointToEnd(head);
    Value hasReceiver = LLVM::ICmpOp::create(
        rewriter, location, LLVM::ICmpPredicate::ne, object,
        LLVM::ZeroOp::create(rewriter, location, pointer));
    cf::CondBranchOp::create(rewriter, location, hasReceiver, lookup,
                             ValueRange{}, nullReceiver, ValueRange{});
    // IEEE 1800-2023 8.4: null instance access is illegal. Keep Talos's
    // diagnosed-error policy, and never load an object header on that path.
    for (auto [failure, status] :
         {std::pair(nullReceiver, TALOS_RT_INVALID_HANDLE),
          std::pair(missing, TALOS_RT_INVALID_ARGUMENT)}) {
      rewriter.setInsertionPointToStart(failure);
      reportManagedStatus(rewriter, location, context,
                          llvmConstant(rewriter, location, i32, status));
      SmallVector<Value> zeros;
      for (Type type : resultTypes)
        zeros.push_back(LLVM::ZeroOp::create(rewriter, location, type));
      cf::BranchOp::create(rewriter, location, continuation, zeros);
    }
    rewriter.setInsertionPointToStart(lookup);
    unsigned alignment = dataLayout.getPointerABIAlignment(0).value();
    // Allocation stores the immutable descriptor pointer in the object's
    // first managed word. GEP uses the target layout, including wasm32.
    Value descriptor =
        LLVM::LoadOp::create(rewriter, location, pointer, object, alignment);
    Value address =
        LLVM::GEPOp::create(rewriter, location, pointer,
                            managedClassDescriptorType(rewriter.getContext()),
                            descriptor, ArrayRef<LLVM::GEPArg>{0, 21});
    Value table =
        LLVM::LoadOp::create(rewriter, location, pointer, address, alignment);
    for (unsigned level = path.second; level != 0; --level) {
      Block *next = block();
      Value present = LLVM::ICmpOp::create(
          rewriter, location, LLVM::ICmpPredicate::ne, table,
          LLVM::ZeroOp::create(rewriter, location, pointer));
      cf::CondBranchOp::create(rewriter, location, present, next, ValueRange{},
                               missing, ValueRange{});
      rewriter.setInsertionPointToStart(next);
      unsigned digit = (path.first >> ((level - 1) * 4)) & 15;
      Value entry = LLVM::GEPOp::create(
          rewriter, location, pointer, pointer, table,
          ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(digit)});
      table =
          LLVM::LoadOp::create(rewriter, location, pointer, entry, alignment);
    }
    Block *invoke = block();
    Value present =
        LLVM::ICmpOp::create(rewriter, location, LLVM::ICmpPredicate::ne, table,
                             LLVM::ZeroOp::create(rewriter, location, pointer));
    cf::CondBranchOp::create(rewriter, location, present, invoke, ValueRange{},
                             missing, ValueRange{});
    rewriter.setInsertionPointToStart(invoke);
    SmallVector<Value> arguments{table, context, receiver};
    SmallVector<Type> argumentTypes{pointer, receiver.getType()};
    for (auto [original, converted] :
         llvm::zip_equal(op.getArguments(), adaptor.getArguments())) {
      if (isa<sim::RefType>(original.getType()) && converted.size() == 1)
        emitNativeStateRetain(rewriter, location, converted.front());
      llvm::append_range(arguments, converted);
      llvm::append_range(argumentTypes, converted.getTypes());
    }
    // IEEE 1800-2023 8.20/8.26 and 13.5: the effective method receives native
    // physical arguments directly. Caller/callee managed-root instrumentation
    // already protects receiver and arguments; dispatch adds no root push or
    // argument/result buffers. The final result always carries unwind status.
    Value callResult =
        LLVM::CallOp::create(
            rewriter, location,
            LLVM::LLVMFunctionType::get(entryResultType, argumentTypes, false),
            arguments)
            .getResult();
    Value status = callResult;
    SmallVector<Value> results;
    if (!resultTypes.empty()) {
      for (unsigned index = 0; index != resultTypes.size(); ++index)
        results.push_back(LLVM::ExtractValueOp::create(rewriter, location,
                                                       callResult, index));
      status = LLVM::ExtractValueOp::create(rewriter, location, callResult,
                                            resultTypes.size());
    }
    reportManagedStatus(rewriter, location, context, status);
    cf::BranchOp::create(rewriter, location, continuation, results);
    SmallVector<SmallVector<Value>> replacements;
    size_t offset = 0;
    for (unsigned count : resultCounts) {
      replacements.emplace_back(merged.begin() + offset,
                                merged.begin() + offset + count);
      offset += count;
    }
    rewriter.replaceOpWithMultiple(op, std::move(replacements));
    return success();
  }

  const llvm::DataLayout &dataLayout;
  const NativeClassLowering &classes;
};

} // namespace

FailureOr<NativeClassLowering> collectNativeClassLowering(ModuleOp module) {
  NativeClassLowering classes;
  SymbolTableCollection symbols;
  WalkResult result = module.walk([&](Operation *operation) -> WalkResult {
    if (auto op = dyn_cast<sim::SimClassFieldRefOp>(operation)) {
      auto field = symbols.lookupNearestSymbolFrom<sim::SimClassFieldDeclOp>(
          op, op.getFieldAttr());
      if (!field || !field.getOffset()) {
        op.emitError("managed class field has no native offset");
        return WalkResult::interrupt();
      }
      classes.fieldOffsets.try_emplace(op, *field.getOffset());
    } else if (auto op = dyn_cast<sim::SimClassVirtualCallOp>(operation)) {
      auto method = symbols.lookupNearestSymbolFrom<sim::SimClassMethodDeclOp>(
          op, op.getMethodAttr());
      auto owner = method
                       ? symbols.lookupNearestSymbolFrom<sim::SimClassDeclOp>(
                             method, method.getOwnerAttr())
                       : sim::SimClassDeclOp{};
      if (!method || !owner) {
        op.emitError("virtual method descriptor is missing");
        return WalkResult::interrupt();
      }
      if (owner.getIsInterface() && !method.getInterfaceOrdinalAttr()) {
        op.emitError("interface method has no dispatch ordinal");
        return WalkResult::interrupt();
      }
      std::optional<std::pair<uint32_t, uint32_t>> path;
      if (auto certificate = native::get<native::MethodVtablePath>(op)) {
        auto values = certificate.asArrayRef();
        if (values.size() != 2 || values[1] <= 0 || values[1] > 8)
          return op.emitError("native method table path is invalid"),
                 WalkResult::interrupt();
        path = std::pair(static_cast<uint32_t>(values[0]),
                         static_cast<uint32_t>(values[1]));
      }
      classes.dispatches.try_emplace(
          op, NativeClassLowering::Dispatch{
                  owner.getId(), method.getInterfaceOrdinal().value_or(0),
                  owner.getIsInterface(), path});
    }
    return WalkResult::advance();
  });
  if (result.wasInterrupted())
    return failure();
  return classes;
}

LogicalResult
materializeManagedMethodThunks(ModuleOp module,
                               const llvm::DataLayout &dataLayout) {
  SmallVector<schedule::NativeMethodOp> methods;
  module.walk([&](schedule::NativeMethodOp method) {
    if (method.getImplementation() &&
        (method.getIsVirtual() ||
         runtime::has<runtime::BytecodeNativeMethod>(method)))
      methods.push_back(method);
  });
  MLIRContext *context = module.getContext();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i32 = IntegerType::get(context, 32);
  Type i64 = IntegerType::get(context, 64);

  SymbolTableCollection symbolTables;
  // One module index serves all thunk replacements. A direct module lookup
  // would scan the growing descriptor and method inventory for every method.
  SymbolTable &moduleSymbols = symbolTables.getSymbolTable(module);
  llvm::DataLayout localDataLayout(dataLayout.getStringRepresentation());
  llvm::LLVMContext llvmContext;
  for (schedule::NativeMethodOp method : methods) {
    std::string thunkName = managedMethodThunkName(method.getSymName());
    if (auto declaration = moduleSymbols.lookup<LLVM::LLVMFuncOp>(thunkName)) {
      auto expected = LLVM::LLVMFunctionType::get(
          i32, {pointer, pointer, pointer, pointer, i32, pointer, i64}, false);
      if (!declaration.isExternal() ||
          declaration.getFunctionType() != expected)
        return declaration.emitError("incompatible native method declaration");
      moduleSymbols.erase(declaration);
    }
    OpBuilder builder(context);
    if (method.getIsTask()) {
      auto implementation =
          symbolTables.lookupNearestSymbolFrom<sim::SimFuncOp>(
              method, method.getImplementationAttr());
      if (!implementation)
        return method.emitError(
            "managed task implementation was not preserved as a process");
      std::string helperName =
          (implementation.getSymName() + ".__talos_activate_checked").str();
      auto helper = symbolTables.lookupNearestSymbolFrom<LLVM::LLVMFuncOp>(
          method, FlatSymbolRefAttr::get(context, helperName));
      if (!helper)
        return method.emitError(
            "managed task implementation has no checked activation helper");
      ArrayRef<Type> helperInputs = helper.getFunctionType().getParams();
      if (helperInputs.size() < 3 || helperInputs.front() != pointer ||
          helperInputs[1] != i64 || helperInputs.back() != pointer)
        return method.emitError(
            "managed task activation helper has an incompatible ABI");
      unsigned physicalArgumentCount = helperInputs.size() - 3;
      FunctionType semanticType = cast<FunctionType>(method.getFunctionType());
      SmallVector<uint64_t> expectedSizes;
      for (Type argument : semanticType.getInputs().drop_front(2)) {
        FailureOr<analysis::SimulationStorageProperties> storage =
            analysis::getSimulationStorageProperties(argument, localDataLayout,
                                                     llvmContext);
        if (failed(storage))
          return method.emitError("managed task argument has no native ABI");
        unsigned planes = analysis::getSimulationPhysicalStorageCount(*storage);
        for (unsigned plane = 0; plane != planes; ++plane)
          expectedSizes.push_back(storage->size);
      }
      if (expectedSizes.size() != physicalArgumentCount)
        return method.emitError(
            "managed task argument flattening is inconsistent");
      builder.setInsertionPointToStart(module.getBody());
      auto thunk = LLVM::LLVMFuncOp::create(
          builder, method.getLoc(), thunkName,
          LLVM::LLVMFunctionType::get(
              i32, {pointer, pointer, pointer, pointer, i32, pointer, i64},
              false),
          LLVM::Linkage::Internal);
      moduleSymbols.insert(thunk);
      copyNativePartition(helper, thunk);
      Block *entry = thunk.addEntryBlock(builder);
      Block *invoke = new Block;
      Block *invalid = new Block;
      SmallVector<Block *> validations(physicalArgumentCount);
      for (Block *&block : validations) {
        block = new Block;
        thunk.getBody().push_back(block);
      }
      thunk.getBody().push_back(invoke);
      thunk.getBody().push_back(invalid);
      builder.setInsertionPointToStart(entry);
      Value countMatches = arith::CmpIOp::create(
          builder, method.getLoc(), arith::CmpIPredicate::eq,
          entry->getArgument(4),
          llvmConstant(builder, method.getLoc(), i32, physicalArgumentCount));
      Value resultSizeMatches = arith::CmpIOp::create(
          builder, method.getLoc(), arith::CmpIPredicate::eq,
          entry->getArgument(6),
          llvmConstant(builder, method.getLoc(), i64, sizeof(uint64_t)));
      Value validABI = arith::AndIOp::create(builder, method.getLoc(),
                                             countMatches, resultSizeMatches);
      LLVM::CondBrOp::create(builder, method.getLoc(), validABI,
                             validations.empty() ? invoke : validations.front(),
                             invalid);

      builder.setInsertionPointToStart(invalid);
      LLVM::ReturnOp::create(builder, method.getLoc(),
                             llvmConstant(builder, method.getLoc(), i32,
                                          TALOS_RT_ARGUMENT_MISMATCH));

      SmallVector<Value> argumentData;
      argumentData.reserve(physicalArgumentCount);
      for (unsigned index = 0; index != physicalArgumentCount; ++index) {
        builder.setInsertionPointToStart(validations[index]);
        Value record = byteGEP(builder, method.getLoc(), entry->getArgument(3),
                               index * 16);
        Value data =
            LLVM::LoadOp::create(builder, method.getLoc(), pointer, record, 8);
        Value size = LLVM::LoadOp::create(
            builder, method.getLoc(), i64,
            byteGEP(builder, method.getLoc(), record, 8), 8);
        Value hasData = LLVM::ICmpOp::create(
            builder, method.getLoc(), LLVM::ICmpPredicate::ne, data,
            LLVM::ZeroOp::create(builder, method.getLoc(), pointer));
        Value sizeMatches = arith::CmpIOp::create(
            builder, method.getLoc(), arith::CmpIPredicate::eq, size,
            llvmConstant(builder, method.getLoc(), i64, expectedSizes[index]));
        Value validRecord = arith::AndIOp::create(builder, method.getLoc(),
                                                  hasData, sizeMatches);
        LLVM::CondBrOp::create(builder, method.getLoc(), validRecord,
                               index + 1 == physicalArgumentCount
                                   ? invoke
                                   : validations[index + 1],
                               invalid);
        argumentData.push_back(data);
      }

      builder.setInsertionPointToStart(invoke);
      SmallVector<Value> callArguments{
          entry->getArgument(0),
          managedObjectHandle(builder, method.getLoc(), entry->getArgument(2))};
      for (unsigned index = 0; index != physicalArgumentCount; ++index) {
        callArguments.push_back(LLVM::LoadOp::create(builder, method.getLoc(),
                                                     helperInputs[index + 2],
                                                     argumentData[index], 1));
      }
      callArguments.push_back(entry->getArgument(5));
      Value status = LLVM::CallOp::create(
                         builder, method.getLoc(), TypeRange{i32},
                         SymbolRefAttr::get(context, helperName), callArguments)
                         .getResult();
      LLVM::ReturnOp::create(builder, method.getLoc(), status);
      continue;
    }
    auto implementation = symbolTables.lookupNearestSymbolFrom<func::FuncOp>(
        method, method.getImplementationAttr());
    if (!implementation)
      return method.emitError(
          "managed method implementation was not lowered to func");
    builder.setInsertionPoint(implementation);
    auto thunk = LLVM::LLVMFuncOp::create(
        builder, method.getLoc(), thunkName,
        LLVM::LLVMFunctionType::get(
            i32, {pointer, pointer, pointer, pointer, i32, pointer, i64},
            false),
        LLVM::Linkage::Internal);
    moduleSymbols.insert(thunk);
    copyNativePartition(implementation, thunk);
    Block *entry = thunk.addEntryBlock(builder);
    builder.setInsertionPointToStart(entry);

    SmallVector<Value> callArguments{entry->getArgument(0)};
    unsigned implicitArguments = method.getIsStatic() ? 1 : 2;
    if (!method.getIsStatic())
      callArguments.push_back(
          managedObjectHandle(builder, method.getLoc(), entry->getArgument(2)));
    FunctionType implementationType = implementation.getFunctionType();
    if (implementationType.getNumInputs() < implicitArguments)
      return method.emitError("managed method implementation has no receiver");
    unsigned physicalArgumentCount =
        implementationType.getNumInputs() - implicitArguments;
    FunctionType semanticType = cast<FunctionType>(method.getFunctionType());
    SmallVector<uint64_t> expectedSizes;
    SmallVector<unsigned> referenceArguments;
    for (Type argument :
         semanticType.getInputs().drop_front(implicitArguments)) {
      auto storage = analysis::getSimulationStorageProperties(
          argument, localDataLayout, llvmContext);
      if (failed(storage))
        return method.emitError("managed method argument has no native ABI");
      if (isa<sim::RefType>(argument))
        referenceArguments.push_back(expectedSizes.size());
      expectedSizes.append(
          analysis::getSimulationPhysicalStorageCount(*storage), storage->size);
    }
    if (expectedSizes.size() != physicalArgumentCount)
      return method.emitError(
          "managed method argument flattening is inconsistent");
    uint64_t expectedResultSize = 0;
    uint32_t expectedResultAlignment = 1;
    for (Type result : semanticType.getResults()) {
      auto storage = analysis::getSimulationStorageProperties(
          result, localDataLayout, llvmContext);
      if (failed(storage))
        return method.emitError("managed method result has no native ABI");
      for (unsigned plane = 0;
           plane != analysis::getSimulationPhysicalStorageCount(*storage);
           ++plane) {
        uint64_t offset;
        if (!alignUp(expectedResultSize, storage->alignment, offset) ||
            storage->size > std::numeric_limits<uint64_t>::max() - offset)
          return method.emitError("managed method result layout overflow");
        expectedResultSize = offset + storage->size;
      }
      expectedResultAlignment =
          std::max(expectedResultAlignment, storage->alignment);
    }
    if (!alignUp(expectedResultSize, expectedResultAlignment,
                 expectedResultSize))
      return method.emitError("managed method result layout overflow");

    // Bytecode marshal plans and foreign native callers share this thunk.
    // Validate the complete ABI before loading any argument or writing a
    // result; a malformed plan must not cause an out-of-bounds native access.
    Block *invoke = new Block;
    Block *invalid = new Block;
    SmallVector<Block *> validations(physicalArgumentCount);
    for (Block *&block : validations) {
      block = new Block;
      thunk.getBody().push_back(block);
    }
    thunk.getBody().push_back(invoke);
    thunk.getBody().push_back(invalid);
    Value countMatches = arith::CmpIOp::create(
        builder, method.getLoc(), arith::CmpIPredicate::eq,
        entry->getArgument(4),
        llvmConstant(builder, method.getLoc(), i32, physicalArgumentCount));
    Value resultSizeMatches = arith::CmpIOp::create(
        builder, method.getLoc(), arith::CmpIPredicate::eq,
        entry->getArgument(6),
        llvmConstant(builder, method.getLoc(), i64, expectedResultSize));
    Value validABI = arith::AndIOp::create(builder, method.getLoc(),
                                           countMatches, resultSizeMatches);
    for (unsigned index : {3u, 5u}) {
      if ((index == 3 && physicalArgumentCount == 0) ||
          (index == 5 && expectedResultSize == 0))
        continue;
      Value hasData = LLVM::ICmpOp::create(
          builder, method.getLoc(), LLVM::ICmpPredicate::ne,
          entry->getArgument(index),
          LLVM::ZeroOp::create(builder, method.getLoc(), pointer));
      validABI =
          arith::AndIOp::create(builder, method.getLoc(), validABI, hasData);
    }
    LLVM::CondBrOp::create(builder, method.getLoc(), validABI,
                           validations.empty() ? invoke : validations.front(),
                           invalid);
    builder.setInsertionPointToStart(invalid);
    LLVM::ReturnOp::create(builder, method.getLoc(),
                           llvmConstant(builder, method.getLoc(), i32,
                                        TALOS_RT_ARGUMENT_MISMATCH));
    SmallVector<Value> argumentData;
    for (unsigned index = 0; index != physicalArgumentCount; ++index) {
      builder.setInsertionPointToStart(validations[index]);
      Value record =
          byteGEP(builder, method.getLoc(), entry->getArgument(3), index * 16);
      Value data =
          LLVM::LoadOp::create(builder, method.getLoc(), pointer, record, 8);
      Value size =
          LLVM::LoadOp::create(builder, method.getLoc(), i64,
                               byteGEP(builder, method.getLoc(), record, 8), 8);
      Value hasData = LLVM::ICmpOp::create(
          builder, method.getLoc(), LLVM::ICmpPredicate::ne, data,
          LLVM::ZeroOp::create(builder, method.getLoc(), pointer));
      Value sizeMatches = arith::CmpIOp::create(
          builder, method.getLoc(), arith::CmpIPredicate::eq, size,
          llvmConstant(builder, method.getLoc(), i64, expectedSizes[index]));
      Value validRecord =
          arith::AndIOp::create(builder, method.getLoc(), hasData, sizeMatches);
      LLVM::CondBrOp::create(
          builder, method.getLoc(), validRecord,
          index + 1 == physicalArgumentCount ? invoke : validations[index + 1],
          invalid);
      argumentData.push_back(data);
    }
    builder.setInsertionPointToStart(invoke);
    for (unsigned index = 0; index != physicalArgumentCount; ++index) {
      Type type = implementationType.getInput(index + implicitArguments);
      callArguments.push_back(LLVM::LoadOp::create(
          builder, method.getLoc(), type, argumentData[index], 1));
    }
    // The erased native ABI borrows its argument words. The implementation
    // consumes one automatic-state reference per ref formal, just as an
    // ordinary native call does (IEEE 1800-2023 8.6 and 13.5). Acquire only
    // after validating every record and roll back if a later acquisition fails.
    SmallVector<Value> acquired;
    for (unsigned index : referenceArguments) {
      Value handle = callArguments[implicitArguments + index];
      Value status =
          LLVM::CallOp::create(builder, method.getLoc(), TypeRange{i32},
                               "talos_rt_v1_native_state_retain",
                               ValueRange{entry->getArgument(0), handle})
              .getResult();
      Block *next = new Block;
      Block *failed = new Block;
      thunk.getBody().push_back(next);
      thunk.getBody().push_back(failed);
      Value ok = LLVM::ICmpOp::create(
          builder, method.getLoc(), LLVM::ICmpPredicate::eq, status,
          llvmConstant(builder, method.getLoc(), i32, TALOS_RT_OK));
      LLVM::CondBrOp::create(builder, method.getLoc(), ok, next, failed);
      builder.setInsertionPointToStart(failed);
      for (Value previous : acquired)
        LLVM::CallOp::create(
            builder, method.getLoc(), TypeRange{i32},
            "talos_rt_v1_native_state_release",
            ValueRange{entry->getArgument(0), previous,
                       llvmConstant(builder, method.getLoc(), i32, 0)});
      LLVM::ReturnOp::create(builder, method.getLoc(), status);
      builder.setInsertionPointToStart(next);
      acquired.push_back(handle);
    }
    auto call = func::CallOp::create(
        builder, method.getLoc(), implementation.getSymName(),
        implementationType.getResults(), callArguments);

    uint64_t resultOffset = 0;
    unsigned physicalResult = 0;
    for (Type resultType : semanticType.getResults()) {
      FailureOr<analysis::SimulationStorageProperties> storage =
          analysis::getSimulationStorageProperties(resultType, localDataLayout,
                                                   llvmContext);
      if (failed(storage))
        return method.emitError("managed method result has no native layout");
      unsigned planes = analysis::getSimulationPhysicalStorageCount(*storage);
      for (unsigned plane = 0; plane != planes; ++plane) {
        if (physicalResult >= call.getNumResults())
          return method.emitError(
              "managed method result flattening is inconsistent");
        uint64_t aligned;
        if (!alignUp(resultOffset, storage->alignment, aligned))
          return method.emitError("managed method result layout overflow");
        resultOffset = aligned;
        LLVM::StoreOp::create(builder, method.getLoc(),
                              call.getResult(physicalResult++),
                              byteGEP(builder, method.getLoc(),
                                      entry->getArgument(5), resultOffset),
                              1);
        if (storage->size > std::numeric_limits<uint64_t>::max() - resultOffset)
          return method.emitError("managed method result layout overflow");
        resultOffset += storage->size;
      }
    }
    Value returnedStatus =
        llvmConstant(builder, method.getLoc(), i32, TALOS_RT_OK);
    if (physicalResult + 1 == call.getNumResults()) {
      Value status = call.getResult(physicalResult);
      if (status.getType() == i32) {
        returnedStatus = status;
        ++physicalResult;
      } else if (isa<runtime::StatusType>(status.getType())) {
        returnedStatus = runtime::RTStatusToBitsOp::create(
            builder, method.getLoc(), i32, status);
        ++physicalResult;
      }
    }
    if (physicalResult != call.getNumResults())
      return method.emitError(
          "managed method result flattening is inconsistent");
    LLVM::ReturnOp::create(builder, method.getLoc(), returnedStatus);
  }
  return materializeTypedNativeMethodEntries(module, dataLayout);
}

void populateManagedToLLVMConversionPatterns(
    RewritePatternSet &patterns, TypeConverter &converter,
    const llvm::DataLayout &dataLayout, uint64_t stateBitCount,
    const NativeClassLowering &classes) {
  MLIRContext *context = patterns.getContext();
  patterns.add<ClassNullConversion, ManagedNullConversion,
               ManagedIdentityEqualConversion<sim::SimSemaphoreEqualOp>,
               ManagedIdentityEqualConversion<sim::SimMailboxEqualOp>,
               ManagedWatchNullConversion, ManagedIsNullConversion,
               EventNullConversion, ClassAllocConversion, ClassCopyConversion,
               ClassBuiltinUpcastConversion, ClassIsInstanceConversion,
               ClassIdConversion, ClassCastConversion, ManagedWatchConversion,
               ClassRootBindConversion,
               ManagedObjectOutputConversion<sim::SimWeakCreateOp>,
               ManagedObjectOutputConversion<sim::SimWeakGetOp>,
               WeakClearConversion, GCSafepointConversion>(converter, context);
  populateManagedContainerToLLVMConversionPatterns(patterns, converter,
                                                   dataLayout);
  populateManagedCoverageToLLVMConversionPatterns(patterns, converter,
                                                  dataLayout, stateBitCount);
  populateManagedReferenceToLLVMConversionPatterns(patterns, converter,
                                                   dataLayout, stateBitCount);
  populateManagedStringToLLVMConversionPatterns(patterns, converter);
  patterns.add<ClassFieldRefConversion>(converter, context, classes);
  patterns.add<ClassVirtualCallConversion>(converter, context, dataLayout,
                                           classes);
}

} // namespace talos::detail
