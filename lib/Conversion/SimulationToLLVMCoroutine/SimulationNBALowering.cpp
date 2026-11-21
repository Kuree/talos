//===- SimulationNBALowering.cpp - Native NBA rewrite patterns ----------===//

#include "SimulationNBALowering.h"
#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "talos/Conversion/SimulationRuntime.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

#include <functional>

using namespace mlir;

namespace talos::detail {
// A guarded two-state body can still produce X/Z at an individual capture
// (for example, from a four-state temporary or an invalid read). Its NBA
// barrier must preserve those captured bits even when the destination has a
// cached knownness certificate (LRM 4.9.4, 10.4.2). Both fixed and dynamic
// generated stages must carry this handoff; a dynamic stage passes only the
// unknown bits that actually overlap its destination.
void emitGeneratedNBAUnknownHandoff(OpBuilder &r, Location loc, uint32_t root,
                                    Value unknown, Block *continuation) {
  auto i64 = r.getI64Type();
  auto pointer = LLVM::LLVMPointerType::get(r.getContext());
  Block *head = r.getInsertionBlock();
  Block *staged =
      r.createBlock(head->getParent(), continuation->getIterator());
  r.setInsertionPointToEnd(head);
  Value hasUnknown = arith::CmpIOp::create(
      r, loc, arith::CmpIPredicate::ne, unknown,
      llvmConstant(r, loc, unknown.getType(), 0));
  cf::CondBranchOp::create(r, loc, hasUnknown, staged, ValueRange{},
                           continuation, ValueRange{});
  r.setInsertionPointToEnd(staged);
  LLVM::StoreOp::create(
      r, loc, llvmConstant(r, loc, r.getI8Type(), 1),
      LLVM::AddressOfOp::create(r, loc, pointer, evalStepFourStateFallbackName),
      1);
  Value roots = byteGEP(
      r, loc,
      LLVM::AddressOfOp::create(r, loc, pointer, evalStepFourStateNBARootsName),
      uint64_t{root / 64} * sizeof(uint64_t));
  Value marked = LLVM::LoadOp::create(r, loc, i64, roots, 8);
  LLVM::StoreOp::create(
      r, loc,
      arith::OrIOp::create(
          r, loc, marked,
          llvmConstant(r, loc, i64, uint64_t{1} << (root % 64))),
      roots, 8);
  cf::BranchOp::create(r, loc, continuation);
  r.setInsertionPointToStart(continuation);
}

namespace {
// LRM 4.3 permits an unobservable immediate update to disappear, but 4.9.4
// still evaluates its RHS and target. Those are independent SSA producers;
// erase only the enqueue. Delayed events can affect time-slot lifetime and
// clocking outputs have additional semantics, so neither is admitted here.
bool canDropUnreadNBA(sim::SimNBAEnqueueOp op,
                      const NativeStaticNBAPlan *plan) {
  auto site = op.getSiteAttr();
  if (!plan || !site || op.getDelay() || site.getTiming() ||
      op.getClockingOutputAttr() ||
      site.getStorage() == schedule::ComputeNBAStorageKind::DynamicFrontier ||
      !isa<sim::RefType>(op.getDestination().getType()) ||
      !sim::getPackedWidth(op.getValue().getType()))
    return false;
  auto root = plan->siteRoots.find(site.getId());
  return root != plan->siteRoots.end() &&
         root->second < plan->unreadRoots.size() &&
         plan->unreadRoots[root->second];
}

static void markGeneratedNBAUnknown(ConversionPatternRewriter &r,
                                     sim::SimNBAEnqueueOp op, uint32_t root,
                                     Value unknown) {
  sim::SimFuncOp function = op->getParentOfType<sim::SimFuncOp>();
  if (!function ||
      !schedule::has<schedule::Field::EvalInductiveTwoState>(function))
    return;
  Block *head = r.getInsertionBlock();
  Block *continuation = r.splitBlock(head, r.getInsertionPoint());
  r.setInsertionPointToEnd(head);
  emitGeneratedNBAUnknownHandoff(r, op.getLoc(), root, unknown, continuation);
}

struct PowerNBAArguments {
  SmallVector<Value> prefix;
  Value value, unknown, guard;
};

template <typename Op, typename Adaptor>
static FailureOr<PowerNBAArguments>
preparePowerNBAArguments(Op op, Adaptor &adaptor, ConversionPatternRewriter &r,
                         uint64_t stateBitCount) {
  if (adaptor.getContext().size() != 1 || adaptor.getValue().empty() ||
      adaptor.getGuard().size() != 1 || adaptor.getDelay().size() > 1)
    return failure();
  Operation *binding = getConvertedObserverBinding(adaptor.getGuard().front());
  if (!binding)
    return failure();
  auto identity = schedule::get<schedule::Field::NativeObserverId>(binding);
  if (!identity) {
    op.emitError("guard has no native observer identity");
    return failure();
  }
  Location loc = op.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(r.getContext());
  Type i64 = r.getI64Type();
  Value spec = entryAlloca(r, loc, i64, 5, 8);
  SmallVector<Value> fields{
      llvmConstant(r, loc, i64, identity.getValue().getZExtValue()),
      adaptor.getDomainEpochRef().front(), adaptor.getDomainEpoch().front(),
      adaptor.getStrategyEpochRef().front(),
      adaptor.getStrategyEpoch().front()};
  for (auto [index, value] : llvm::enumerate(fields))
    LLVM::StoreOp::create(r, loc, value, byteGEP(r, loc, spec, index * 8), 8);
  auto spill = [&](Value value) {
    Value address = entryAlloca(r, loc, value.getType(), 1, 1);
    LLVM::StoreOp::create(r, loc, value, address, 1);
    return address;
  };
  Value null = LLVM::ZeroOp::create(r, loc, pointer);
  Value unknown =
      adaptor.getValue().size() == 2 ? spill(adaptor.getValue()[1]) : null;
  Value unknownPlane = adaptor.getValue().size() == 2
                           ? detail::createStatePlaneAddress(
                                 r, loc, schedule::StatePlane::Unknown)
                           : null;
  SmallVector<Value> prefix{
      adaptor.getContext().front(),
      detail::createStatePlaneAddress(r, loc, schedule::StatePlane::Value),
      unknownPlane, llvmConstant(r, loc, i64, stateBitCount)};
  return PowerNBAArguments{std::move(prefix), spill(adaptor.getValue().front()),
                           unknown, spec};
}

static void finishPowerNBAConversion(Operation *op, Value context,
                                     StringRef function, ValueRange arguments,
                                     ConversionPatternRewriter &r) {
  Value status = LLVM::CallOp::create(
                     r, op->getLoc(), TypeRange{r.getI32Type()},
                     SymbolRefAttr::get(r.getContext(), function), arguments)
                     .getResult();
  LLVM::CallOp::create(
      r, op->getLoc(), TypeRange{},
      SymbolRefAttr::get(r.getContext(), "talos_rt_v1_scheduler_fail"),
      ValueRange{context, status});
  r.eraseOp(op);
}

class PowerNBAConversion final
    : public OpConversionPattern<sim::SimPowerNBAOp> {
public:
  PowerNBAConversion(const TypeConverter &converter, MLIRContext *context,
                     uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}
  LogicalResult matchAndRewrite(sim::SimPowerNBAOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &r) const override {
    if (adaptor.getBacking().size() != 1 || adaptor.getVisible().size() != 1)
      return failure();
    auto prepared = preparePowerNBAArguments(op, adaptor, r, stateBitCount);
    if (failed(prepared))
      return failure();
    auto &arguments = prepared->prefix;
    arguments.append(
        {adaptor.getBacking().front(), adaptor.getVisible().front(),
         llvmConstant(r, op.getLoc(), r.getI64Type(),
                      *sim::getPackedWidth(op.getValue().getType()))});
    if (!adaptor.getDelay().empty())
      arguments.push_back(adaptor.getDelay().front());
    arguments.append({prepared->value, prepared->unknown, prepared->guard});
    finishPowerNBAConversion(op, adaptor.getContext().front(),
                             adaptor.getDelay().empty()
                                 ? "talos_rt_v1_power_nba"
                                 : "talos_rt_v1_power_nba_after",
                             arguments, r);
    return success();
  }

private:
  uint64_t stateBitCount;
};

class PowerNBAViewConversion final
    : public OpConversionPattern<sim::SimPowerNBAViewOp> {
public:
  PowerNBAViewConversion(const TypeConverter &converter, MLIRContext *context,
                         uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}
  LogicalResult matchAndRewrite(sim::SimPowerNBAViewOp op,
                                OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &r) const override {
    if (adaptor.getRoot().size() != 1 || adaptor.getStart().size() != 1 ||
        adaptor.getLower().size() != 1 || adaptor.getUpper().size() != 1 ||
        adaptor.getValid().size() != 1)
      return failure();
    auto prepared = preparePowerNBAArguments(op, adaptor, r, stateBitCount);
    if (failed(prepared))
      return failure();
    auto &arguments = prepared->prefix;
    Location loc = op.getLoc();
    Type i64 = r.getI64Type();
    arguments.append(
        {adaptor.getRoot().front(),
         llvmConstant(
             r, loc, i64,
             *nativeStateWidth(op.getRoot().getType().getElementType())),
         adaptor.getStart().front(), adaptor.getLower().front(),
         adaptor.getUpper().front(),
         LLVM::ZExtOp::create(r, loc, r.getI32Type(),
                              adaptor.getValid().front()),
         llvmConstant(r, loc, i64,
                      *sim::getPackedWidth(op.getValue().getType())),
         adaptor.getDelay().empty() ? llvmConstant(r, loc, i64, 0)
                                    : adaptor.getDelay().front(),
         prepared->value, prepared->unknown, prepared->guard});
    finishPowerNBAConversion(op, adaptor.getContext().front(),
                             "talos_rt_v1_power_nba_view", arguments, r);
    return success();
  }

private:
  uint64_t stateBitCount;
};

class PowerCancelNBAConversion final
    : public OpConversionPattern<sim::SimPowerCancelNBAOp> {
public:
  using OpConversionPattern::OpConversionPattern;
  LogicalResult
  matchAndRewrite(sim::SimPowerCancelNBAOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getContext().size() != 1 || adaptor.getTarget().size() != 1)
      return failure();
    Type i32 = rewriter.getI32Type();
    Value status =
        LLVM::CallOp::create(
            rewriter, op.getLoc(), TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_power_cancel_nba"),
            ValueRange{adaptor.getContext().front(),
                       adaptor.getTarget().front(),
                       llvmConstant(rewriter, op.getLoc(),
                                    rewriter.getI64Type(), op.getWidth())})
            .getResult();
    LLVM::CallOp::create(
        rewriter, op.getLoc(), TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{adaptor.getContext().front(), status});
    rewriter.eraseOp(op);
    return success();
  }
};

class InertialDriverConversion final
    : public OpConversionPattern<sim::SimDriverDriveInertialOp> {
public:
  InertialDriverConversion(const TypeConverter &converter, MLIRContext *context,
                           uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}

  LogicalResult
  matchAndRewrite(sim::SimDriverDriveInertialOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getDriver().size() != 1 || adaptor.getValue().empty() ||
        adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1)
      return failure();
    std::optional<unsigned> width = nativeStateWidth(op.getValue().getType());
    if (!width)
      return failure();

    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value value = savePlane(adaptor.getValue().front());
    Value unknown = LLVM::ZeroOp::create(rewriter, location, pointer);
    Value unknownPlane = LLVM::ZeroOp::create(rewriter, location, pointer);
    if (adaptor.getValue().size() == 2) {
      unknown = savePlane(adaptor.getValue()[1]);
      unknownPlane = detail::createStatePlaneAddress(
          rewriter, location, schedule::StatePlane::Unknown);
    }
    uint32_t flags = 0;
    if (op.getVectorDelay())
      flags |= TALOS_RT_INERTIAL_DRIVER_VECTOR_DELAY;
    if (op.getDeferResolution())
      flags |= TALOS_RT_INERTIAL_DRIVER_DEFER_RESOLUTION;
    if (sim::has<sim::metadata::UserNetRawDrive>(op))
      flags |= TALOS_RT_INERTIAL_DRIVER_PUBLISH_RAW;
    if (op.getValue().getType().isF32())
      flags |= TALOS_RT_INERTIAL_DRIVER_REAL32;
    if (op.getValue().getType().isF64())
      flags |= TALOS_RT_INERTIAL_DRIVER_REAL64;
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_scheduler_inertial_driver"),
            ValueRange{
                runtimeContext,
                detail::createStatePlaneAddress(rewriter, location,
                                                schedule::StatePlane::Value),
                unknownPlane,
                llvmConstant(rewriter, location, i64, stateBitCount),
                adaptor.getDriver().front(),
                llvmConstant(rewriter, location, i64, *width),
                llvmConstant(rewriter, location, i64, op.getCodeUnitId()),
                llvmConstant(rewriter, location, i32, op.getComponent()),
                llvmConstant(rewriter, location, i32, flags),
                adaptor.getRiseDelay().front(), adaptor.getFallDelay().front(),
                adaptor.getTurnoffDelay().front(), value, unknown})
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
};

class InertialPathDriverConversion final
    : public OpConversionPattern<sim::SimDriverDriveInertialPathOp> {
public:
  InertialPathDriverConversion(const TypeConverter &converter,
                               MLIRContext *context, uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}

  LogicalResult
  matchAndRewrite(sim::SimDriverDriveInertialPathOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getDriver().size() != 1 || adaptor.getValue().empty() ||
        adaptor.getActiveMask().size() != 1 ||
        adaptor.getRiseMask().size() != 1 ||
        adaptor.getFallMask().size() != 1 ||
        adaptor.getTurnoffMask().size() != 1 ||
        adaptor.getPulseTransitionMasks().size() > 1 ||
        adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1)
      return failure();
    std::optional<unsigned> width = nativeStateWidth(op.getValue().getType());
    if (!width)
      return failure();

    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value value = savePlane(adaptor.getValue().front());
    Value unknown = LLVM::ZeroOp::create(rewriter, location, pointer);
    Value unknownPlane = LLVM::ZeroOp::create(rewriter, location, pointer);
    if (adaptor.getValue().size() == 2) {
      unknown = savePlane(adaptor.getValue()[1]);
      unknownPlane = detail::createStatePlaneAddress(
          rewriter, location, schedule::StatePlane::Unknown);
    }
    bool pulseControlled = !adaptor.getPulseTransitionMasks().empty();
    uint32_t flags = 0;
    if (op.getDeferResolution())
      flags |= TALOS_RT_INERTIAL_DRIVER_DEFER_RESOLUTION;
    if (sim::has<sim::metadata::UserNetRawDrive>(op))
      flags |= TALOS_RT_INERTIAL_DRIVER_PUBLISH_RAW;
    if (op.getPulseOnDetect())
      flags |= TALOS_RT_INERTIAL_PATH_ON_DETECT;
    if (op.getPulseShowCancelled())
      flags |= TALOS_RT_INERTIAL_PATH_SHOW_CANCELLED;
    if (op.getPulseTransitionMasks())
      flags |= TALOS_RT_INERTIAL_PATH_EXACT_TRANSITIONS;
    SmallVector<Value, 23> arguments{
        runtimeContext,
        detail::createStatePlaneAddress(rewriter, location,
                                        schedule::StatePlane::Value),
        unknownPlane,
        llvmConstant(rewriter, location, i64, stateBitCount),
        adaptor.getDriver().front(),
        llvmConstant(rewriter, location, i64, *width),
        llvmConstant(rewriter, location, i64, op.getCodeUnitId()),
        llvmConstant(rewriter, location, i32, op.getComponent()),
        llvmConstant(rewriter, location, i32, op.getGroup()),
        llvmConstant(rewriter, location, i32, op.getGroupCount()),
        llvmConstant(rewriter, location, i32, flags),
        adaptor.getRiseDelay().front(),
        adaptor.getFallDelay().front(),
        adaptor.getTurnoffDelay().front()};
    if (pulseControlled) {
      arguments.push_back(llvmConstant(
          rewriter, location, i64, static_cast<uint64_t>(op.getPulseReject())));
      arguments.push_back(llvmConstant(
          rewriter, location, i64, static_cast<uint64_t>(op.getPulseError())));
    }
    arguments.push_back(value);
    arguments.push_back(unknown);
    arguments.push_back(savePlane(adaptor.getActiveMask().front()));
    arguments.push_back(savePlane(adaptor.getRiseMask().front()));
    arguments.push_back(savePlane(adaptor.getFallMask().front()));
    arguments.push_back(savePlane(adaptor.getTurnoffMask().front()));
    if (pulseControlled)
      arguments.push_back(savePlane(adaptor.getPulseTransitionMasks().front()));
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(
                rewriter.getContext(),
                pulseControlled
                    ? "talos_rt_v1_scheduler_inertial_path_driver_pulse"
                    : "talos_rt_v1_scheduler_inertial_path_driver"),
            arguments)
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
};

class InertialPathStorageConversion final
    : public OpConversionPattern<sim::SimRefStoreInertialPathOp> {
public:
  InertialPathStorageConversion(const TypeConverter &converter,
                                MLIRContext *context, uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}

  LogicalResult
  matchAndRewrite(sim::SimRefStoreInertialPathOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getReference().size() != 1 || adaptor.getValue().empty() ||
        adaptor.getWriteMask().size() != 1 ||
        adaptor.getActiveMask().size() != 1 ||
        adaptor.getRiseMask().size() != 1 ||
        adaptor.getFallMask().size() != 1 ||
        adaptor.getTurnoffMask().size() != 1 ||
        adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1)
      return failure();
    std::optional<unsigned> width = nativeStateWidth(op.getValue().getType());
    if (!width)
      return failure();

    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value value = savePlane(adaptor.getValue().front());
    Value unknown = LLVM::ZeroOp::create(rewriter, location, pointer);
    Value unknownPlane = LLVM::ZeroOp::create(rewriter, location, pointer);
    if (adaptor.getValue().size() == 2) {
      unknown = savePlane(adaptor.getValue()[1]);
      unknownPlane = detail::createStatePlaneAddress(
          rewriter, location, schedule::StatePlane::Unknown);
    }
    bool pulseControlled = !adaptor.getPulseTransitionMasks().empty();
    SmallVector<Value, 24> arguments{
        runtimeContext,
        detail::createStatePlaneAddress(rewriter, location,
                                        schedule::StatePlane::Value),
        unknownPlane,
        llvmConstant(rewriter, location, i64, stateBitCount),
        adaptor.getReference().front(),
        llvmConstant(rewriter, location, i64, *width),
        llvmConstant(rewriter, location, i64, op.getSiteId()),
        llvmConstant(rewriter, location, i32, op.getComponent()),
        llvmConstant(rewriter, location, i32, op.getGroup()),
        llvmConstant(rewriter, location, i32, op.getGroupCount()),
        llvmConstant(rewriter, location, i32, op.getNonblocking())};
    if (pulseControlled) {
      arguments.push_back(llvmConstant(
          rewriter, location, i32,
          (op.getPulseOnDetect() ? TALOS_RT_INERTIAL_PATH_ON_DETECT : 0) |
              (op.getPulseShowCancelled()
                   ? TALOS_RT_INERTIAL_PATH_SHOW_CANCELLED
                   : 0) |
              (op.getPulseTransitionMasks()
                   ? TALOS_RT_INERTIAL_PATH_EXACT_TRANSITIONS
                   : 0)));
    }
    arguments.push_back(adaptor.getRiseDelay().front());
    arguments.push_back(adaptor.getFallDelay().front());
    arguments.push_back(adaptor.getTurnoffDelay().front());
    if (pulseControlled) {
      arguments.push_back(llvmConstant(
          rewriter, location, i64, static_cast<uint64_t>(op.getPulseReject())));
      arguments.push_back(llvmConstant(
          rewriter, location, i64, static_cast<uint64_t>(op.getPulseError())));
    }
    arguments.push_back(value);
    arguments.push_back(unknown);
    arguments.push_back(savePlane(adaptor.getWriteMask().front()));
    arguments.push_back(savePlane(adaptor.getActiveMask().front()));
    arguments.push_back(savePlane(adaptor.getRiseMask().front()));
    arguments.push_back(savePlane(adaptor.getFallMask().front()));
    arguments.push_back(savePlane(adaptor.getTurnoffMask().front()));
    if (pulseControlled)
      arguments.push_back(savePlane(adaptor.getPulseTransitionMasks().front()));
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(
                rewriter.getContext(),
                pulseControlled
                    ? "talos_rt_v1_scheduler_inertial_path_storage_pulse"
                    : "talos_rt_v1_scheduler_inertial_path_storage"),
            arguments)
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
};

class InertialStrengthPairConversion final
    : public OpConversionPattern<sim::SimDriverDriveInertialStrengthPairOp> {
public:
  InertialStrengthPairConversion(const TypeConverter &converter,
                                 MLIRContext *context, uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}

  LogicalResult
  matchAndRewrite(sim::SimDriverDriveInertialStrengthPairOp op,
                  OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getLowDriver().size() != 1 ||
        adaptor.getHighDriver().size() != 1 ||
        adaptor.getLowValue().size() != 2 ||
        adaptor.getHighValue().size() != 2 ||
        adaptor.getTransitionValue().size() != 2 ||
        adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1)
      return failure();
    std::optional<unsigned> width =
        nativeStateWidth(op.getLowValue().getType());
    if (!width)
      return failure();

    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value lowValue = savePlane(adaptor.getLowValue()[0]);
    Value lowUnknown = savePlane(adaptor.getLowValue()[1]);
    Value highValue = savePlane(adaptor.getHighValue()[0]);
    Value highUnknown = savePlane(adaptor.getHighValue()[1]);
    Value transitionValue = savePlane(adaptor.getTransitionValue()[0]);
    Value transitionUnknown = savePlane(adaptor.getTransitionValue()[1]);
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(
                rewriter.getContext(),
                "talos_rt_v1_scheduler_inertial_driver_strength_pair"),
            ValueRange{
                runtimeContext,
                detail::createStatePlaneAddress(rewriter, location,
                                                schedule::StatePlane::Value),
                detail::createStatePlaneAddress(rewriter, location,
                                                schedule::StatePlane::Unknown),
                llvmConstant(rewriter, location, i64, stateBitCount),
                adaptor.getLowDriver().front(), adaptor.getHighDriver().front(),
                llvmConstant(rewriter, location, i64, *width),
                llvmConstant(rewriter, location, i64, op.getCodeUnitId()),
                llvmConstant(rewriter, location, i32, op.getComponent()),
                adaptor.getRiseDelay().front(), adaptor.getFallDelay().front(),
                adaptor.getTurnoffDelay().front(), lowValue, lowUnknown,
                highValue, highUnknown, transitionValue, transitionUnknown})
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
};

class InertialPathStrengthPairConversion final
    : public OpConversionPattern<
          sim::SimDriverDriveInertialPathStrengthPairOp> {
public:
  InertialPathStrengthPairConversion(const TypeConverter &converter,
                                     MLIRContext *context,
                                     uint64_t stateBitCount)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount) {}

  LogicalResult
  matchAndRewrite(sim::SimDriverDriveInertialPathStrengthPairOp op,
                  OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getLowDriver().size() != 1 ||
        adaptor.getHighDriver().size() != 1 ||
        adaptor.getLowValue().size() != 2 ||
        adaptor.getHighValue().size() != 2 ||
        adaptor.getTransitionValue().size() != 2 ||
        adaptor.getActiveMask().size() != 1 ||
        adaptor.getRiseMask().size() != 1 ||
        adaptor.getFallMask().size() != 1 ||
        adaptor.getTurnoffMask().size() != 1 ||
        adaptor.getRiseDelay().size() != 1 ||
        adaptor.getFallDelay().size() != 1 ||
        adaptor.getTurnoffDelay().size() != 1)
      return failure();
    std::optional<unsigned> width =
        nativeStateWidth(op.getLowValue().getType());
    if (!width)
      return failure();
    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    SmallVector<Value> arguments{
        runtimeContext,
        detail::createStatePlaneAddress(rewriter, location,
                                        schedule::StatePlane::Value),
        detail::createStatePlaneAddress(rewriter, location,
                                        schedule::StatePlane::Unknown),
        llvmConstant(rewriter, location, i64, stateBitCount),
        adaptor.getLowDriver().front(),
        adaptor.getHighDriver().front(),
        llvmConstant(rewriter, location, i64, *width),
        llvmConstant(rewriter, location, i64, op.getCodeUnitId()),
        llvmConstant(rewriter, location, i32, op.getComponent()),
        llvmConstant(rewriter, location, i32, op.getGroup()),
        llvmConstant(rewriter, location, i32, op.getGroupCount())};
    bool pulseControlled = !adaptor.getPulseTransitionMasks().empty();
    if (pulseControlled) {
      uint32_t flags =
          TALOS_RT_INERTIAL_PATH_EXACT_TRANSITIONS |
          (op.getPulseOnDetect() ? TALOS_RT_INERTIAL_PATH_ON_DETECT : 0) |
          (op.getPulseShowCancelled() ? TALOS_RT_INERTIAL_PATH_SHOW_CANCELLED
                                      : 0);
      arguments.push_back(llvmConstant(rewriter, location, i32, flags));
    }
    llvm::append_range(arguments,
                       ValueRange{adaptor.getRiseDelay().front(),
                                  adaptor.getFallDelay().front(),
                                  adaptor.getTurnoffDelay().front()});
    if (pulseControlled) {
      arguments.push_back(
          llvmConstant(rewriter, location, i64, op.getPulseReject()));
      arguments.push_back(
          llvmConstant(rewriter, location, i64, op.getPulseError()));
    }
    llvm::append_range(arguments,
                       ValueRange{savePlane(adaptor.getLowValue()[0]),
                                  savePlane(adaptor.getLowValue()[1]),
                                  savePlane(adaptor.getHighValue()[0]),
                                  savePlane(adaptor.getHighValue()[1]),
                                  savePlane(adaptor.getTransitionValue()[0]),
                                  savePlane(adaptor.getTransitionValue()[1]),
                                  savePlane(adaptor.getActiveMask().front()),
                                  savePlane(adaptor.getRiseMask().front()),
                                  savePlane(adaptor.getFallMask().front()),
                                  savePlane(adaptor.getTurnoffMask().front())});
    if (pulseControlled)
      arguments.push_back(savePlane(adaptor.getPulseTransitionMasks().front()));
    StringRef function =
        pulseControlled
            ? "talos_rt_v1_scheduler_inertial_path_strength_pair_pulse"
            : "talos_rt_v1_scheduler_inertial_path_strength_pair";
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(), function), arguments)
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
};

/// Preserve the declaration boundary of a dynamic packed reference through
/// native lowering. A stable handle records only a root-relative offset; the
/// input reference type supplies the narrower view width needed to clip a
/// partial NBA without spilling into an adjacent aggregate element.
class PackedSliceNBAConversion final
    : public OpConversionPattern<sim::SimNBAEnqueueOp> {
public:
  PackedSliceNBAConversion(const TypeConverter &converter, MLIRContext *context,
                           uint64_t stateBitCount,
                           const NativeStaticNBAPlan *staticPlan,
                           const NativeStateLayout *stateLayout,
                           bool staticSitesEnabled, bool guardedClaims,
                           const DenseSet<Operation *> &completePackedSliceNBAs)
      : OpConversionPattern(converter, context, PatternBenefit(2)),
        stateBitCount(stateBitCount), staticPlan(staticPlan),
        stateLayout(stateLayout), staticSitesEnabled(staticSitesEnabled),
        guardedClaims(guardedClaims),
        completePackedSliceNBAs(completePackedSliceNBAs) {}

  LogicalResult
  matchAndRewrite(sim::SimNBAEnqueueOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (canDropUnreadNBA(op, staticPlan)) {
      rewriter.eraseOp(op);
      return success();
    }
    auto view = op.getDestination().getDefiningOp<sim::SimRefDynExtractOp>();
    if (!view || adaptor.getValue().empty() ||
        adaptor.getDestination().size() != 1)
      return failure();
    // IEEE 1800-2023 11.5.1: the source range proof excludes partial overlap
    // with this packed view. Ordinary NBA lowering retains X/Z and enclosing
    // array guards (7.4.5), captures the target and value now (4.9.4, 10.4.2),
    // and stages the complete payload in the AOT queue.
    if (completePackedSliceNBAs.contains(op))
      return failure();
    std::optional<unsigned> baseWidth =
        sim::getPackedWidth(view.getInput().getType().getElementType());
    std::optional<unsigned> sourceWidth =
        nativeStateWidth(op.getValue().getType());
    if (!baseWidth || !sourceWidth || *baseWidth == 0 || *sourceWidth == 0)
      return failure();

    Value base = rewriter.getRemappedValue(view.getInput());
    SmallVector<Value> lowPlanes;
    if (!base ||
        failed(rewriter.getRemappedValues(view.getLowBit(), lowPlanes)) ||
        lowPlanes.empty() || lowPlanes.size() > 2)
      return failure();

    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    SignedI64Index low =
        resizeSignedIndexToI64(rewriter, location, lowPlanes.front());
    Value valid = low.representable;
    if (lowPlanes.size() == 2) {
      Value known = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::eq, lowPlanes[1],
          arith::ConstantOp::create(
              rewriter, location, lowPlanes[1].getType(),
              rewriter.getZeroAttr(lowPlanes[1].getType())));
      valid = arith::AndIOp::create(rewriter, location, valid, known);
    }
    // Dynamic-reference lowering may have consumed an unknown index plane
    // while building a guarded stable handle.  Preserve that exact validity
    // predicate, but not the selected handle result: direct staging needs the
    // former to make an X/Z write a no-op (IEEE 1800-2017 11.5.1), while
    // retaining the latter would keep native_handle_offset on the hot path.
    Value directValid = valid;
    bool exactDestinationValidity = true;
    Operation *destinationSelect =
        adaptor.getDestination().front().getDefiningOp();
    if (isa_and_nonnull<arith::SelectOp, LLVM::SelectOp>(destinationSelect)) {
      std::optional<uint64_t> trueValue =
          resolveCFGConstantInteger(destinationSelect->getOperand(1));
      std::optional<uint64_t> falseValue =
          resolveCFGConstantInteger(destinationSelect->getOperand(2));
      Value condition = destinationSelect->getOperand(0);
      if (falseValue && *falseValue == UINT64_MAX) {
        directValid =
            arith::AndIOp::create(rewriter, location, directValid, condition);
      } else if (trueValue && *trueValue == UINT64_MAX) {
        Value inverted = arith::XOrIOp::create(
            rewriter, location, condition,
            llvmConstant(rewriter, location, rewriter.getI1Type(), 1));
        directValid =
            arith::AndIOp::create(rewriter, location, directValid, inverted);
      } else {
        exactDestinationValidity = false;
      }
    }
    schedule::NBASiteAttr site = op.getSiteAttr();
    bool mappedSite =
        site && staticPlan && staticPlan->siteRoots.contains(site.getId());
    uint32_t plannedRoot =
        mappedSite ? staticPlan->siteRoots.lookup(site.getId()) : UINT32_MAX;
    bool staticallyStaged =
        !op.getClockingOutputAttr() && staticSitesEnabled && staticPlan &&
        mappedSite && staticPlan->mergeSafeRoots[plannedRoot] &&
        adaptor.getDelay().empty() && !site.getTiming() &&
        site.getStorage() != schedule::ComputeNBAStorageKind::DynamicFrontier;

    uint32_t rootIndex = UINT32_MAX;
    if (staticallyStaged) {
      auto staticRoot = staticPlan->siteRoots.find(site.getId());
      if (staticRoot != staticPlan->siteRoots.end())
        rootIndex = staticRoot->second;
    }
    std::function<std::optional<uint64_t>(Value)> resolveViewOffset =
        [&](Value reference) -> std::optional<uint64_t> {
      if (reference.getDefiningOp<sim::SimContextStorageOp>())
        return 0;
      // Capture specialization replaces direct descriptor arguments with a
      // context-storage op. A surviving entry argument can be a runtime view;
      // descriptor provenance alone does not prove root-relative offset zero.
      if (auto argument = dyn_cast<BlockArgument>(reference)) {
        auto owner =
            dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
        if (!owner || argument.getOwner() != &owner.getBody().front() ||
            !::talos::schedule::has<::talos::schedule::Field::EvalRawCaptures>(
                owner) ||
            !stateLayout || rootIndex == UINT32_MAX || !staticPlan ||
            rootIndex >= staticPlan->roots.size())
          return std::nullopt;
        auto descriptor = owner.getArgAttrOfType<IntegerAttr>(
            argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
        auto handle = descriptor
                          ? stateLayout->storage.find(descriptor.getInt())
                          : stateLayout->storage.end();
        talos_rt_stable_handle_v1 decoded{};
        if (handle == stateLayout->storage.end() ||
            !talos_rt_stable_handle_decode(handle->second, &decoded) ||
            decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC ||
            decoded.id != staticPlan->roots[rootIndex].static_state ||
            decoded.offset < 0)
          return std::nullopt;
        return static_cast<uint64_t>(decoded.offset);
      }
      if (auto extract = reference.getDefiningOp<sim::SimRefExtractOp>()) {
        std::optional<uint64_t> parent = resolveViewOffset(extract.getInput());
        if (!parent || extract.getLowBit() > UINT64_MAX - *parent)
          return std::nullopt;
        return *parent + extract.getLowBit();
      }
      if (auto subelement =
              reference.getDefiningOp<sim::SimRefSubelementOp>()) {
        std::optional<uint64_t> parent =
            resolveViewOffset(subelement.getInput());
        if (!parent)
          return std::nullopt;
        uint64_t offset = *parent;
        Type type = subelement.getInput().getType().getElementType();
        for (int64_t rawIndex : subelement.getIndices()) {
          if (rawIndex < 0)
            return std::nullopt;
          auto child = sim::getAggregateProvenanceSubelement(
              type, static_cast<unsigned>(rawIndex));
          if (!child || child->first > UINT64_MAX - offset)
            return std::nullopt;
          offset += child->first;
          type = sim::getAggregateElementType(type,
                                              static_cast<unsigned>(rawIndex));
        }
        return offset;
      }
      return std::nullopt;
    };

    // Inspect original Simulation reference provenance only when it can enable
    // the generated static path. Generic conversion may already have rewritten
    // producers while legalizing an unplanned function, so needlessly walking
    // that IR is both wasted compile time and unsafe during dialect conversion.
    std::optional<uint64_t> viewOffset;
    if (staticallyStaged && rootIndex != UINT32_MAX)
      viewOffset = resolveViewOffset(view.getInput());
    StringRef generatedAccumulator =
        staticPlan && rootIndex < staticPlan->generatedAccumulators.size()
            ? staticPlan->generatedAccumulators[rootIndex]
            : StringRef{};
    uint64_t rootWidth = staticPlan && rootIndex < staticPlan->roots.size()
                             ? staticPlan->roots[rootIndex].bit_width
                             : 0;
    sim::SimFuncOp function = op->getParentOfType<sim::SimFuncOp>();
    uint32_t homeRegion =
        function ? getRuntimeEventRegion(function.getHomeRegion()) : UINT32_MAX;
    uint32_t commitRegion = homeRegion == TALOS_RT_REGION_ACTIVE ||
                                    homeRegion == TALOS_RT_REGION_REACTIVE
                                ? homeRegion + 2
                                : UINT32_MAX;
    bool scalarValue =
        llvm::all_of(
            adaptor.getValue(),
            [](Value value) { return isa<IntegerType>(value.getType()); }) ||
        (adaptor.getValue().size() == 1 &&
         isa<LLVM::LLVMPointerType>(adaptor.getValue().front().getType()));
    bool directGeneratedStage =
        staticallyStaged && rootIndex != UINT32_MAX &&
        !generatedAccumulator.empty() && rootWidth <= 64 && viewOffset &&
        *viewOffset <= rootWidth && *baseWidth <= rootWidth - *viewOffset &&
        commitRegion != UINT32_MAX && scalarValue && exactDestinationValidity;

    auto widen = [&](Value value) {
      if (isa<LLVM::LLVMPointerType>(value.getType()))
        value = LLVM::LoadOp::create(
            rewriter, location,
            IntegerType::get(rewriter.getContext(), *sourceWidth), value, 1);
      auto type = cast<IntegerType>(value.getType());
      return type.getWidth() >= 64
                 ? value
                 : LLVM::ZExtOp::create(rewriter, location, i64, value)
                       .getResult();
    };
    auto emitDirectGeneratedStage = [&] {
      Value zero = llvmConstant(rewriter, location, i64, 0);
      Value sourceWidthValue =
          llvmConstant(rewriter, location, i64, *sourceWidth);
      Value baseWidthValue = llvmConstant(rewriter, location, i64, *baseWidth);
      Value lowerBound = llvmConstant(rewriter, location, i64,
                                      -static_cast<int64_t>(*sourceWidth));
      Value belowEnd =
          arith::CmpIOp::create(rewriter, location, arith::CmpIPredicate::slt,
                                low.value, baseWidthValue);
      Value aboveBegin = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::sgt, low.value, lowerBound);
      Value overlaps = arith::AndIOp::create(
          rewriter, location, directValid,
          arith::AndIOp::create(rewriter, location, belowEnd, aboveBegin));
      Value lowPositive = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::sgt, low.value, zero);
      Value start = arith::SelectOp::create(rewriter, location, lowPositive,
                                            low.value, zero);
      Value rawEnd = arith::AddIOp::create(rewriter, location, low.value,
                                           sourceWidthValue);
      Value endBelowBound =
          arith::CmpIOp::create(rewriter, location, arith::CmpIPredicate::slt,
                                rawEnd, baseWidthValue);
      Value end = arith::SelectOp::create(rewriter, location, endBelowBound,
                                          rawEnd, baseWidthValue);
      Value overlapWidth =
          arith::SubIOp::create(rewriter, location, end, start);
      Value sourceStart =
          arith::SubIOp::create(rewriter, location, start, low.value);
      Value destinationStart = arith::AddIOp::create(
          rewriter, location, start,
          llvmConstant(rewriter, location, i64, *viewOffset));
      Value safeWidth = arith::SelectOp::create(rewriter, location, overlaps,
                                                overlapWidth, zero);
      Value safeSource = arith::SelectOp::create(rewriter, location, overlaps,
                                                 sourceStart, zero);
      Value safeDestination = arith::SelectOp::create(
          rewriter, location, overlaps, destinationStart, zero);
      Value widthIs64 = arith::CmpIOp::create(
          rewriter, location, arith::CmpIPredicate::eq, safeWidth,
          llvmConstant(rewriter, location, i64, 64));
      Value maskShift = arith::SelectOp::create(
          rewriter, location, widthIs64,
          llvmConstant(rewriter, location, i64, 63), safeWidth);
      Value lowMask = arith::SubIOp::create(
          rewriter, location,
          arith::ShLIOp::create(rewriter, location,
                                llvmConstant(rewriter, location, i64, 1),
                                maskShift),
          llvmConstant(rewriter, location, i64, 1));
      lowMask = arith::SelectOp::create(
          rewriter, location, widthIs64,
          llvmConstant(rewriter, location, i64, UINT64_MAX), lowMask);
      Value mask =
          arith::ShLIOp::create(rewriter, location, lowMask, safeDestination);
      Value sourceValue = widen(adaptor.getValue().front());
      Value sourceUnknown =
          llvmConstant(rewriter, location, sourceValue.getType(), 0);
      if (adaptor.getValue().size() == 2)
        sourceUnknown = widen(adaptor.getValue()[1]);
      auto position = [&](Value source) {
        // A scalar root may capture a wider part-select. Clip in the source
        // type before truncating: a negative index can select payload bits
        // above bit 63 (IEEE 1800-2023 11.5.1, 4.9.4).
        Value shift = safeSource;
        if (source.getType() != i64)
          shift =
              LLVM::ZExtOp::create(rewriter, location, source.getType(), shift);
        Value selected =
            arith::ShRUIOp::create(rewriter, location, source, shift);
        if (selected.getType() != i64)
          selected = LLVM::TruncOp::create(rewriter, location, i64, selected);
        return arith::AndIOp::create(rewriter, location,
                                     arith::ShLIOp::create(rewriter, location,
                                                           selected,
                                                           safeDestination),
                                     mask);
      };
      Value positionedValue = position(sourceValue);
      Value positionedUnknown = position(sourceUnknown);
      if (adaptor.getValue().size() == 2)
        markGeneratedNBAUnknown(rewriter, op, rootIndex, positionedUnknown);
      Value accumulator = schedule::NativeNBAAccumulatorAddressOp::create(
          rewriter, location, generatedAccumulator);
      if (rootIndex < staticPlan->trackTransients.size() &&
          staticPlan->trackTransients[rootIndex])
        emitGeneratedNBATransient(rewriter, location, accumulator, 0, mask,
                                  positionedValue, positionedUnknown);
      auto mergeField = [&](NBAField field, Value positioned) {
        Value previous = schedule::NativeNBAAccumulatorLoadOp::create(
            rewriter, location, i64, accumulator, field, 0, 8);
        Value merged = arith::OrIOp::create(
            rewriter, location,
            arith::AndIOp::create(
                rewriter, location, previous,
                arith::XOrIOp::create(
                    rewriter, location, mask,
                    llvmConstant(rewriter, location, i64, UINT64_MAX))),
            positioned);
        schedule::NativeNBAAccumulatorStoreOp::create(
            rewriter, location, merged, accumulator, field, 0, 8);
      };
      mergeField(NBAField::Value, positionedValue);
      mergeField(NBAField::Unknown, positionedUnknown);
      Value previousMask = schedule::NativeNBAAccumulatorLoadOp::create(
          rewriter, location, i64, accumulator, NBAField::WriteMask, 0, 8);
      schedule::NativeNBAAccumulatorStoreOp::create(
          rewriter, location,
          arith::OrIOp::create(rewriter, location, previousMask, mask),
          accumulator, NBAField::WriteMask, 0, 8);
      Value previousValid = schedule::NativeNBAAccumulatorLoadOp::create(
          rewriter, location, i32, accumulator, NBAField::Valid, 0, 4);
      schedule::NativeNBAAccumulatorStoreOp::create(
          rewriter, location,
          arith::OrIOp::create(
              rewriter, location, previousValid,
              LLVM::ZExtOp::create(rewriter, location, i32, overlaps)),
          accumulator, NBAField::Valid, 0, 4);
      schedule::NativeNBAAccumulatorStoreOp::create(
          rewriter, location,
          llvmConstant(rewriter, location, i32, commitRegion), accumulator,
          NBAField::ExecRegion, 0, 4);
      Value dirtyBit =
          arith::SelectOp::create(rewriter, location, overlaps,
                                  llvmConstant(rewriter, location, i64,
                                               uint64_t{1} << (rootIndex % 64)),
                                  zero);
      // A variable overlap/mask keeps the fixed-slot canonical capture ABI.
      // These RMWs do not query private captures in the same leaf/page, and
      // cannot be admitted as unconditional scalar producers (LRM 4.9.4).
      constexpr auto dirtyRoots = schedule::NBAIndex::DirtyRoots;
      constexpr auto dirtySummary = schedule::NBAIndex::DirtySummary;
      uint32_t dirtyWord = rootIndex / 64;
      Value previousDirty =
          loadNBAIndex(rewriter, location, dirtyRoots, dirtyWord, rootIndex,
                       /*canonicalCapture=*/true);
      storeNBAIndex(
          rewriter, location,
          arith::OrIOp::create(rewriter, location, previousDirty, dirtyBit),
          dirtyRoots, dirtyWord, rootIndex, /*canonicalCapture=*/true);
      Value summaryBit =
          arith::SelectOp::create(rewriter, location, overlaps,
                                  llvmConstant(rewriter, location, i64,
                                               uint64_t{1} << (dirtyWord % 64)),
                                  zero);
      Value previousSummary =
          loadNBAIndex(rewriter, location, dirtySummary, dirtyWord / 64,
                       rootIndex, /*canonicalCapture=*/true);
      storeNBAIndex(
          rewriter, location,
          arith::OrIOp::create(rewriter, location, previousSummary, summaryBit),
          dirtySummary, dirtyWord / 64, rootIndex, /*canonicalCapture=*/true);
    };

    Block *guardContinuation = nullptr;
    if (directGeneratedStage) {
      bool assumeClean =
          ::talos::schedule::has<assumeCleanSpecializationAttr>(op);
      bool useGuardedClaim = !assumeClean && guardedClaims;
      if (!useGuardedClaim) {
        emitDirectGeneratedStage();
        rewriter.eraseOp(op);
        return success();
      }
      Value useDirect = staticNBASpecializationGuard(
          rewriter, location, rootIndex,
          staticPlan->guardedMergeRoots[rootIndex]);
      Block *head = rewriter.getInsertionBlock();
      guardContinuation =
          rewriter.splitBlock(head, rewriter.getInsertionPoint());
      Region *region = head->getParent();
      Block *direct =
          rewriter.createBlock(region, guardContinuation->getIterator());
      Block *fallback =
          rewriter.createBlock(region, guardContinuation->getIterator());
      rewriter.setInsertionPointToEnd(head);
      markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useDirect,
                                              direct, ValueRange{}, fallback,
                                              ValueRange{}));
      rewriter.setInsertionPointToEnd(direct);
      emitDirectGeneratedStage();
      cf::BranchOp::create(rewriter, location, guardContinuation);
      rewriter.setInsertionPointToEnd(fallback);
    }

    // Generic fallback consumes the converted handle contract.  Build this
    // only after the direct path has returned: otherwise its handle-offset
    // call remains artificially live in a runtime-free eval body even though
    // direct staging has already reconstructed index knownness and bounds.
    valid = arith::AndIOp::create(
        rewriter, location, valid,
        arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::ne,
            adaptor.getDestination().front(),
            llvmConstant(rewriter, location, i64, UINT64_MAX)));
    Value valid32 = LLVM::ZExtOp::create(rewriter, location, i32, valid);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value value = savePlane(adaptor.getValue().front());
    Value unknown = LLVM::ZeroOp::create(rewriter, location, pointer);
    Value unknownPlane = LLVM::ZeroOp::create(rewriter, location, pointer);
    if (adaptor.getValue().size() == 2) {
      unknown = savePlane(adaptor.getValue()[1]);
      unknownPlane = detail::createStatePlaneAddress(
          rewriter, location, schedule::StatePlane::Unknown);
    }
    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    Value delay = adaptor.getDelay().empty()
                      ? llvmConstant(rewriter, location, i64, 0)
                      : adaptor.getDelay().front();
    Value staticSite = llvmConstant(
        rewriter, location, i64, staticallyStaged ? site.getId() : UINT64_MAX);
    Value clockingOutput =
        llvmConstant(rewriter, location, i64,
                     op.getClockingOutputAttr()
                         ? op.getClockingOutputAttr().getValue().getZExtValue()
                         : UINT64_MAX);
    Value status =
        LLVM::CallOp::create(
            rewriter, location, TypeRange{i32},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_scheduler_packed_slice_nba"),
            ValueRange{runtimeContext,
                       detail::createStatePlaneAddress(
                           rewriter, location, schedule::StatePlane::Value),
                       unknownPlane,
                       llvmConstant(rewriter, location, i64, stateBitCount),
                       base, llvmConstant(rewriter, location, i64, *baseWidth),
                       low.value, valid32,
                       llvmConstant(rewriter, location, i64, *sourceWidth),
                       delay, staticSite, clockingOutput, value, unknown})
            .getResult();
    LLVM::CallOp::create(
        rewriter, location, TypeRange{},
        SymbolRefAttr::get(rewriter.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{runtimeContext, status});
    if (guardContinuation) {
      cf::BranchOp::create(rewriter, location, guardContinuation);
      rewriter.setInsertionPointToStart(guardContinuation);
    }
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount = 0;
  const NativeStaticNBAPlan *staticPlan = nullptr;
  const NativeStateLayout *stateLayout = nullptr;
  bool staticSitesEnabled = false;
  bool guardedClaims = false;
  const DenseSet<Operation *> &completePackedSliceNBAs;
};

// Compare both canonical planes within the exact captured target. The byte
// window may straddle a machine word; neighboring bits are excluded.
Value buildGeneratedNBAChange(OpBuilder &builder, Location location,
                              uint64_t bitOffset, unsigned width, Value value,
                              Value unknown) {
  auto resultType = cast<IntegerType>(value.getType());
  assert(width > 0 && width <= resultType.getWidth());
  unsigned firstBit = bitOffset % 8;
  auto spanType =
      IntegerType::get(builder.getContext(), ((width + firstBit + 7) / 8) * 8);
  auto loadCurrent = [&](schedule::StatePlane plane) -> Value {
    Value current = schedule::NativeStateLoadOp::create(
        builder, location, spanType, plane, Value{}, bitOffset / 8, 1);
    if (firstBit)
      current = arith::ShRUIOp::create(
          builder, location, current,
          llvmConstant(builder, location, spanType, firstBit));
    return resizeNativeInteger(builder, location, current, resultType);
  };
  Value changed = arith::XOrIOp::create(
      builder, location, value, loadCurrent(schedule::StatePlane::Value));
  if (unknown)
    changed = arith::OrIOp::create(
        builder, location, changed,
        arith::XOrIOp::create(builder, location, unknown,
                              loadCurrent(schedule::StatePlane::Unknown)));
  if (width == resultType.getWidth())
    return changed;
  Value mask = LLVM::ConstantOp::create(
      builder, location, resultType,
      builder.getIntegerAttr(
          resultType, APInt::getLowBitsSet(resultType.getWidth(), width)));
  return arith::AndIOp::create(builder, location, changed, mask);
}

class ImmediateNBAConversion final
    : public OpConversionPattern<sim::SimNBAEnqueueOp> {
public:
  ImmediateNBAConversion(const TypeConverter &converter, MLIRContext *context,
                         uint64_t stateBitCount,
                         const NativeStaticNBAPlan *staticPlan,
                         const NativeStateLayout *stateLayout,
                         bool staticSitesEnabled, bool guardedClaims)
      : OpConversionPattern(converter, context), stateBitCount(stateBitCount),
        staticPlan(staticPlan), stateLayout(stateLayout),
        staticSitesEnabled(staticSitesEnabled), guardedClaims(guardedClaims) {}

  LogicalResult
  matchAndRewrite(sim::SimNBAEnqueueOp op, OneToNOpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    if (canDropUnreadNBA(op, staticPlan)) {
      rewriter.eraseOp(op);
      return success();
    }
    if (adaptor.getDestination().size() != 1 || adaptor.getValue().empty())
      return failure();
    std::optional<unsigned> width = nativeStateWidth(op.getValue().getType());
    if (!width)
      return failure();
    Location location = op.getLoc();
    Type pointer = LLVM::LLVMPointerType::get(rewriter.getContext());
    Type i32 = rewriter.getI32Type();
    Type i64 = rewriter.getI64Type();
    sim::SimFuncOp function = op->getParentOfType<sim::SimFuncOp>();
    bool driverDestination =
        isa<sim::DriverType>(op.getDestination().getType());
    bool inductiveTwoStateAccess = ::talos::schedule::has<
        ::talos::schedule::Field::EvalInductiveTwoStateAccess>(op);
    // Selected eval bodies execute only after their complete closure crosses
    // a known quiescent boundary, so they can use fixed root/region metadata.
    // That function-level fact does not prove exclusive ownership of an NBA
    // accumulator, however: a coincident four-state writer may have staged X
    // first. Preserve the selected unknown-plane overwrite, including zero,
    // to retain NBA execution order (IEEE 1800-2023 4.6(b), 10.4.2).
    // IEEE 1800-2023 4.4.2.4, 4.5: a shared runtime NBA barrier must see
    // validity, masks and region even when all payload bits are known.
    bool compactEvalMetadata =
        !::talos::schedule::has<::talos::schedule::Field::EvalRuntimeCalendar>(
            op->getParentOfType<ModuleOp>()) &&
        (inductiveTwoStateAccess ||
         ::talos::schedule::has<schedule::metadata::evalCompactNBAMetadata>(
             op));

    schedule::NBASiteAttr site = op.getSiteAttr();
    auto staticRoot =
        site && staticPlan
            ? staticPlan->siteRoots.find(site.getId())
            : llvm::DenseMap<uint64_t, uint32_t>::const_iterator{};
    // The dirty index represents validity only for a certified generated
    // capture. Unproved roots retain the canonical fields and page index.
    compactEvalMetadata &=
        staticPlan && staticRoot != staticPlan->siteRoots.end() &&
        staticRoot->second < staticPlan->generatedCompactStages.size() &&
        staticPlan->generatedCompactStages[staticRoot->second];
    std::optional<uint64_t> destinationValue =
        resolveCFGConstantInteger(adaptor.getDestination().front());
    talos_rt_stable_handle_v1 decoded{};
    bool packedStaticStage =
        !op.getClockingOutputAttr() && !driverDestination && site &&
        staticPlan && staticRoot != staticPlan->siteRoots.end() &&
        staticRoot->second < staticPlan->roots.size() &&
        staticPlan->mergeSafeRoots[staticRoot->second] &&
        adaptor.getDelay().empty() && !site.getTiming() &&
        site.getStorage() != schedule::ComputeNBAStorageKind::DynamicFrontier &&
        *width <= 64 && destinationValue &&
        talos_rt_stable_handle_decode(*destinationValue, &decoded) &&
        decoded.kind == TALOS_RT_STABLE_HANDLE_STATIC &&
        decoded.id == staticPlan->roots[staticRoot->second].static_state &&
        decoded.offset >= 0 &&
        static_cast<uint64_t>(decoded.offset) <=
            staticPlan->roots[staticRoot->second].bit_width &&
        *width <= staticPlan->roots[staticRoot->second].bit_width -
                      static_cast<uint64_t>(decoded.offset) &&
        (llvm::all_of(
             adaptor.getValue(),
             [](Value value) { return isa<IntegerType>(value.getType()); }) ||
         (*width <= 64 && adaptor.getValue().size() == 1 &&
          isa<LLVM::LLVMPointerType>(adaptor.getValue().front().getType())));
    // Wide Eval sites need the per-site ordering/ingress preflight in AOT
    // materialization. Preserve their site identity in the static NBA ABI;
    // the ordinary actor still uses the existing accumulator/claim route.
    bool wideEvalSite =
        packedStaticStage && function &&
        ::talos::schedule::has<::talos::schedule::Field::EvalRawCaptures>(
            function) &&
        staticPlan->roots[staticRoot->second].bit_width > 64;
    if (packedStaticStage && !wideEvalSite) {
      bool assumeClean =
          ::talos::schedule::has<assumeCleanSpecializationAttr>(op);
      StringRef generatedAccumulator =
          staticRoot->second < staticPlan->generatedAccumulators.size()
              ? staticPlan->generatedAccumulators[staticRoot->second]
              : StringRef{};
      bool useGuardedClaim =
          !assumeClean && (guardedClaims || generatedAccumulator.empty());
      auto widen = [&](Value value) {
        if (isa<LLVM::LLVMPointerType>(value.getType()))
          value = LLVM::LoadOp::create(
              rewriter, location,
              IntegerType::get(rewriter.getContext(), *width), value, 1);
        auto type = cast<IntegerType>(value.getType());
        return type.getWidth() == 64
                   ? value
                   : LLVM::ZExtOp::create(rewriter, location, i64, value)
                         .getResult();
      };
      Value unknown = llvmConstant(rewriter, location, i64, 0);
      if (adaptor.getValue().size() == 2)
        unknown = widen(adaptor.getValue()[1]);
      if (inductiveTwoStateAccess)
        unknown = llvmConstant(rewriter, location, i64, 0);
      // A two-state eval copy normally stages known values, and the two-state
      // NBA commits replace staged unknown data with zero. A payload that is
      // not inductively two-state can still compute X/Z (a ?: join, a case
      // default, x/0, an out-of-range read), and the update must store exactly
      // that value (IEEE 1800-2023 10.4.2, 4.4.2.4). When this activation
      // stages unknown bits, send its step to the four-state commit and mark
      // the root so it is not committed as fast two-state data.
      if (!inductiveTwoStateAccess && !generatedAccumulator.empty() &&
          adaptor.getValue().size() == 2)
        markGeneratedNBAUnknown(rewriter, op, staticRoot->second, unknown);
      Value value = widen(adaptor.getValue().front());
      uint32_t homeRegion =
          function ? getRuntimeEventRegion(function.getHomeRegion())
                   : UINT32_MAX;
      uint32_t commitRegion = homeRegion == TALOS_RT_REGION_ACTIVE ||
                                      homeRegion == TALOS_RT_REGION_REACTIVE
                                  ? homeRegion + 2
                                  : UINT32_MAX;
      uint64_t rootWidth = staticPlan->roots[staticRoot->second].bit_width;
      bool directLaneStage = !generatedAccumulator.empty() && *width == 32 &&
                             adaptor.getValue().size() == 1 &&
                             (decoded.offset & 31) == 0;
      bool directPartialScalarStage =
          !generatedAccumulator.empty() && rootWidth <= 64;
      bool directGeneratedStage = commitRegion != UINT32_MAX &&
                                  (directPartialScalarStage || directLaneStage);
      // The certified target of this capture: root, static state, width,
      // mask, commit region and source site.
      auto captureSpec = [&] {
        uint64_t origin = site.getId();
        if (auto source = schedule::get<schedule::Field::EvalOriginNbaSite>(op))
          origin = source.getValue().getZExtValue();
        else if (auto source =
                     staticPlan->siteSemanticOrigins.find(site.getId());
                 source != staticPlan->siteSemanticOrigins.end())
          origin = source->second;
        // LRM 4.9.4/10.4.2: the target and RHS are captured together.
        // Descriptor provenance alone did not authorize this literal mask.
        uint64_t mask =
            (*width == 64 ? UINT64_MAX : (uint64_t{1} << *width) - 1)
            << decoded.offset;
        return rewriter.getDenseI64ArrayAttr(
            {staticRoot->second,
             staticPlan->roots[staticRoot->second].static_state,
             static_cast<int64_t>(rootWidth), static_cast<int64_t>(mask),
             commitRegion, static_cast<int64_t>(origin)});
      };
      auto emitDirectGeneratedStage = [&] {
        Block *unchangedContinuation = nullptr;
        if (directPartialScalarStage &&
            staticPlan->canDiscardUnchanged(staticRoot->second, site.getId(),
                                            decoded.offset, *width)) {
          // Retain RHS/target evaluation, and never discard a write that may
          // overwrite an earlier pending NBA (LRM 4.6, 4.9.4, 10.4.2).
          // The shared dirty index covers both runtime and generated stages.
          // The plan separately excludes intervening immediate writers.
          uint64_t bitOffset =
              staticPlan->generatedOffsets[staticRoot->second] + decoded.offset;
          Value changed = buildGeneratedNBAChange(rewriter, location, bitOffset,
                                                  *width, value, unknown);
          Value dirty =
              loadNBAIndex(rewriter, location, schedule::NBAIndex::DirtyRoots,
                           staticRoot->second / 64, staticRoot->second);
          Value pending = arith::AndIOp::create(
              rewriter, location, dirty,
              llvmConstant(rewriter, location, i64,
                           uint64_t{1} << (staticRoot->second % 64)));
          Value needed = arith::CmpIOp::create(
              rewriter, location, arith::CmpIPredicate::ne,
              arith::OrIOp::create(rewriter, location, changed, pending),
              llvmConstant(rewriter, location, i64, 0));
          Block *head = rewriter.getInsertionBlock();
          unchangedContinuation =
              rewriter.splitBlock(head, rewriter.getInsertionPoint());
          Block *stage = rewriter.createBlock(
              head->getParent(), unchangedContinuation->getIterator());
          rewriter.setInsertionPointToEnd(head);
          cf::CondBranchOp::create(rewriter, location, needed, stage,
                                   ValueRange{}, unchangedContinuation,
                                   ValueRange{});
          rewriter.setInsertionPointToEnd(stage);
        }
        bool fixedRegionEvalStage =
            compactEvalMetadata &&
            staticRoot->second < staticPlan->generatedCommitRegions.size() &&
            staticPlan->generatedCommitRegions[staticRoot->second] !=
                UINT32_MAX;
        bool fullRootEvalStage =
            fixedRegionEvalStage &&
            staticRoot->second < staticPlan->generatedFullRootStages.size() &&
            staticPlan->generatedFullRootStages[staticRoot->second];
        uint64_t fixedWriteMask =
            staticRoot->second < staticPlan->generatedFixedWriteMasks.size()
                ? staticPlan->generatedFixedWriteMasks[staticRoot->second]
                : 0;
        Value base = schedule::NativeNBAAccumulatorAddressOp::create(
            rewriter, location, generatedAccumulator);
        if (directPartialScalarStage) {
          uint64_t sourceMask =
              *width == 64 ? UINT64_MAX : (uint64_t{1} << *width) - 1;
          uint64_t mask = sourceMask << decoded.offset;
          auto mergeField = [&](NBAField field, Value fieldValue) {
            Value positioned = fieldValue;
            if (decoded.offset != 0)
              positioned = arith::ShLIOp::create(
                  rewriter, location, positioned,
                  llvmConstant(rewriter, location, i64, decoded.offset));
            Value masked = arith::AndIOp::create(
                rewriter, location, positioned,
                llvmConstant(rewriter, location, i64, mask));
            Value merged = masked;
            if (!compactEvalMetadata || fixedWriteMask == 0) {
              Value old = schedule::NativeNBAAccumulatorLoadOp::create(
                  rewriter, location, i64, base, field, 0, 8);
              merged = arith::OrIOp::create(
                  rewriter, location,
                  arith::AndIOp::create(
                      rewriter, location, old,
                      llvmConstant(rewriter, location, i64, ~mask)),
                  masked);
            }
            schedule::NativeNBAAccumulatorStoreOp::create(
                rewriter, location, merged, base, field, 0, 8);
          };
          if (staticRoot->second < staticPlan->trackTransients.size() &&
              staticPlan->trackTransients[staticRoot->second]) {
            auto position = [&](Value fieldValue) -> Value {
              Value positioned = fieldValue;
              if (decoded.offset != 0)
                positioned = arith::ShLIOp::create(
                    rewriter, location, positioned,
                    llvmConstant(rewriter, location, i64, decoded.offset));
              return arith::AndIOp::create(
                  rewriter, location, positioned,
                  llvmConstant(rewriter, location, i64, mask));
            };
            // A compact stage does not maintain write_mask, and a compact
            // and a full body may stage one root in the same barrier. When
            // every write to the root covers the same bits, the dirty bit that
            // both set says whether this barrier already staged them.
            bool planFullRoot =
                staticRoot->second <
                    staticPlan->generatedFullRootStages.size() &&
                staticPlan->generatedFullRootStages[staticRoot->second];
            Value staged;
            if (planFullRoot || fixedWriteMask != 0) {
              Value dirty = loadNBAIndex(
                  rewriter, location, schedule::NBAIndex::DirtyRoots,
                  staticRoot->second / 64, staticRoot->second);
              Value bit = arith::AndIOp::create(
                  rewriter, location, dirty,
                  llvmConstant(rewriter, location, i64,
                               uint64_t{1} << (staticRoot->second % 64)));
              staged = arith::SelectOp::create(
                  rewriter, location,
                  arith::CmpIOp::create(
                      rewriter, location, arith::CmpIPredicate::ne, bit,
                      llvmConstant(rewriter, location, i64, 0)),
                  llvmConstant(rewriter, location, i64, mask),
                  llvmConstant(rewriter, location, i64, 0));
            }
            emitGeneratedNBATransient(
                rewriter, location, base, 0,
                llvmConstant(rewriter, location, i64, mask), position(value),
                position(unknown), staged);
          }
          mergeField(NBAField::Value, value);
          // A promoted body can share the generated accumulator with a
          // four-state bootstrap or fallback body.  Explicitly overwrite its
          // selected unknown bits with zero: otherwise a later mixed or
          // checkpoint barrier can replay stale X/Z data from the prior
          // phase into canonical state.
          mergeField(NBAField::Unknown, unknown);
          if (!compactEvalMetadata ||
              (!fullRootEvalStage && fixedWriteMask == 0)) {
            Value oldMask = schedule::NativeNBAAccumulatorLoadOp::create(
                rewriter, location, i64, base, NBAField::WriteMask, 0, 8);
            schedule::NativeNBAAccumulatorStoreOp::create(
                rewriter, location,
                arith::OrIOp::create(
                    rewriter, location, oldMask,
                    llvmConstant(rewriter, location, i64, mask)),
                base, NBAField::WriteMask, 0, 8);
          }
        } else {
          uint64_t laneOffset = static_cast<uint64_t>(decoded.offset / 8);
          Value laneValue =
              LLVM::TruncOp::create(rewriter, location, i32, value);
          schedule::NativeNBAAccumulatorStoreOp::create(
              rewriter, location, laneValue, base, NBAField::Value, laneOffset,
              4);
          // This lane form is restricted to two-state values, but the same
          // accumulator can have been populated by a four-state phase before
          // promotion.  Clear the selected unknown lane as part of staging so
          // every legal barrier observes the same known value.
          schedule::NativeNBAAccumulatorStoreOp::create(
              rewriter, location,
              llvmConstant(rewriter, location, i32, UINT32_MAX), base,
              NBAField::WriteMask, laneOffset, 4);
          schedule::NativeNBAAccumulatorStoreOp::create(
              rewriter, location, llvmConstant(rewriter, location, i32, 0),
              base, NBAField::Unknown, laneOffset, 4);
        }
        if (!fixedRegionEvalStage) {
          schedule::NativeNBAAccumulatorStoreOp::create(
              rewriter, location, llvmConstant(rewriter, location, i32, 1),
              base, NBAField::Valid, 0, 4);
          schedule::NativeNBAAccumulatorStoreOp::create(
              rewriter, location,
              llvmConstant(rewriter, location, i32, commitRegion), base,
              NBAField::ExecRegion, 0, 4);
        }
        uint32_t dirtyWordIndex = staticRoot->second / 64;
        Value previous =
            loadNBAIndex(rewriter, location, schedule::NBAIndex::DirtyRoots,
                         dirtyWordIndex, staticRoot->second);
        Value marked = LLVM::OrOp::create(
            rewriter, location, previous,
            llvmConstant(rewriter, location, i64,
                         uint64_t{1} << (staticRoot->second % 64)));
        storeNBAIndex(rewriter, location, marked,
                      schedule::NBAIndex::DirtyRoots, dirtyWordIndex,
                      staticRoot->second)
            .setCaptureAttr(captureSpec());
        if (!compactEvalMetadata) {
          // This is a producer's canonical RMW, not a query of every root in
          // the summary page: it keeps the root's role so private pending
          // scopes remain local (LRM 4.9.4/10.4.2).
          Value previousSummary =
              loadNBAIndex(rewriter, location, schedule::NBAIndex::DirtySummary,
                           dirtyWordIndex / 64, staticRoot->second);
          Value markedSummary = LLVM::OrOp::create(
              rewriter, location, previousSummary,
              llvmConstant(rewriter, location, i64,
                           uint64_t{1} << (dirtyWordIndex % 64)));
          storeNBAIndex(rewriter, location, markedSummary,
                        schedule::NBAIndex::DirtySummary, dirtyWordIndex / 64,
                        staticRoot->second);
        }
        if (unchangedContinuation) {
          cf::BranchOp::create(rewriter, location, unchangedContinuation);
          rewriter.setInsertionPointToStart(unchangedContinuation);
        }
      };
      if (!useGuardedClaim && directGeneratedStage) {
        emitDirectGeneratedStage();
        rewriter.eraseOp(op);
        return success();
      }
      if (useGuardedClaim && directGeneratedStage) {
        Value useDirect = staticNBASpecializationGuard(
            rewriter, location, staticRoot->second,
            staticPlan->guardedMergeRoots[staticRoot->second]);
        Block *head = rewriter.getInsertionBlock();
        Block *continuation =
            rewriter.splitBlock(head, rewriter.getInsertionPoint());
        Region *region = head->getParent();
        Block *directBlock =
            rewriter.createBlock(region, continuation->getIterator());
        Block *claimBlock =
            rewriter.createBlock(region, continuation->getIterator());

        rewriter.setInsertionPointToEnd(head);
        markLikelyTrue(cf::CondBranchOp::create(rewriter, location, useDirect,
                                                directBlock, ValueRange{},
                                                claimBlock, ValueRange{}));

        rewriter.setInsertionPointToEnd(directBlock);
        emitDirectGeneratedStage();
        cf::BranchOp::create(rewriter, location, continuation);

        rewriter.setInsertionPointToEnd(claimBlock);
        Value contextAddress = LLVM::AddressOfOp::create(
            rewriter, location, pointer, "__talos_current_context");
        Value runtimeContext = LLVM::LoadOp::create(rewriter, location, pointer,
                                                    contextAddress, 8);
        Value status =
            LLVM::CallOp::create(
                rewriter, location, TypeRange{i32},
                SymbolRefAttr::get(rewriter.getContext(),
                                   "talos_rt_v1_static_nba_claim"),
                ValueRange{
                    runtimeContext,
                    llvmConstant(rewriter, location, i32, staticRoot->second),
                    detail::createStatePlaneAddress(
                        rewriter, location, schedule::StatePlane::Value),
                    LLVM::ZeroOp::create(rewriter, location, pointer),
                    llvmConstant(rewriter, location, i64, stateBitCount),
                    llvmConstant(rewriter, location, i64,
                                 static_cast<uint64_t>(decoded.offset)),
                    llvmConstant(rewriter, location, i64, *width), value,
                    unknown})
                .getResult();
        schedule::set<schedule::Field::EvalPendingStageSpec>(
            status.getDefiningOp(), captureSpec());
        LLVM::CallOp::create(rewriter, location, TypeRange{},
                             SymbolRefAttr::get(rewriter.getContext(),
                                                "talos_rt_v1_scheduler_fail"),
                             ValueRange{runtimeContext, status});
        cf::BranchOp::create(rewriter, location, continuation);

        rewriter.setInsertionPointToStart(continuation);
        rewriter.eraseOp(op);
        return success();
      }
      Value contextAddress = LLVM::AddressOfOp::create(
          rewriter, location, pointer, "__talos_current_context");
      Value runtimeContext =
          LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
      if (!useGuardedClaim) {
        LLVM::CallOp::create(
            rewriter, location, TypeRange{},
            SymbolRefAttr::get(rewriter.getContext(),
                               "talos_rt_v1_static_nba_stage_wide"),
            ValueRange{
                runtimeContext,
                llvmConstant(rewriter, location, i32, staticRoot->second),
                llvmConstant(rewriter, location, i64,
                             static_cast<uint64_t>(decoded.offset)),
                llvmConstant(rewriter, location, i64, *width), value, unknown,
                llvmConstant(rewriter, location, i32,
                             adaptor.getValue().size() == 2 ? 1 : 0)});
        rewriter.eraseOp(op);
        return success();
      }
      Value status =
          LLVM::CallOp::create(
              rewriter, location, TypeRange{i32},
              SymbolRefAttr::get(rewriter.getContext(),
                                 "talos_rt_v1_static_nba_claim"),
              ValueRange{
                  runtimeContext,
                  llvmConstant(rewriter, location, i32, staticRoot->second),
                  detail::createStatePlaneAddress(rewriter, location,
                                                  schedule::StatePlane::Value),
                  adaptor.getValue().size() == 2
                      ? detail::createStatePlaneAddress(
                            rewriter, location, schedule::StatePlane::Unknown)
                      : LLVM::ZeroOp::create(rewriter, location, pointer)
                            .getResult(),
                  llvmConstant(rewriter, location, i64, stateBitCount),
                  llvmConstant(rewriter, location, i64,
                               static_cast<uint64_t>(decoded.offset)),
                  llvmConstant(rewriter, location, i64, *width), value,
                  unknown})
              .getResult();
      LLVM::CallOp::create(rewriter, location, TypeRange{},
                           SymbolRefAttr::get(rewriter.getContext(),
                                              "talos_rt_v1_scheduler_fail"),
                           ValueRange{runtimeContext, status});
      rewriter.eraseOp(op);
      return success();
    }

    Value contextAddress = LLVM::AddressOfOp::create(
        rewriter, location, pointer, "__talos_current_context");
    Value runtimeContext =
        LLVM::LoadOp::create(rewriter, location, pointer, contextAddress, 8);
    auto savePlane = [&](Value value) {
      Value address = entryAlloca(rewriter, location, value.getType(), 1, 1);
      LLVM::StoreOp::create(rewriter, location, value, address, 1);
      return address;
    };
    Value value = savePlane(adaptor.getValue().front());
    Value unknown = LLVM::ZeroOp::create(rewriter, location, pointer);
    Value unknownPlane = LLVM::ZeroOp::create(rewriter, location, pointer);
    if (adaptor.getValue().size() == 2) {
      unknown = savePlane(adaptor.getValue()[1]);
      unknownPlane = detail::createStatePlaneAddress(
          rewriter, location, schedule::StatePlane::Unknown);
    }
    Value valuePlane = detail::createStatePlaneAddress(
        rewriter, location, schedule::StatePlane::Value);
    Value delay = adaptor.getDelay().empty()
                      ? llvmConstant(rewriter, location, i64, 0)
                      : adaptor.getDelay().front();
    if (isa<sim::StringType>(op.getValue().getType())) {
      Value status =
          LLVM::CallOp::create(
              rewriter, location, TypeRange{i32},
              SymbolRefAttr::get(rewriter.getContext(),
                                 "talos_rt_v1_scheduler_string_nba"),
              ValueRange{runtimeContext, valuePlane,
                         llvmConstant(rewriter, location, i64, stateBitCount),
                         adaptor.getDestination().front(), delay,
                         adaptor.getValue().front()})
              .getResult();
      LLVM::CallOp::create(rewriter, location, TypeRange{},
                           SymbolRefAttr::get(rewriter.getContext(),
                                              "talos_rt_v1_scheduler_fail"),
                           ValueRange{runtimeContext, status});
    } else {
      bool mappedSite =
          site && staticPlan && staticPlan->siteRoots.contains(site.getId());
      uint32_t rootIndex =
          mappedSite ? staticPlan->siteRoots.lookup(site.getId()) : UINT32_MAX;
      bool orderedEvalQueue =
          function &&
          ::talos::schedule::has<::talos::schedule::Field::EvalOrderedNbaQueue>(
              function);
      talos_rt_stable_handle_v1 destination{};
      auto holdTarget = destinationValue;
      bool fixedHold = false;
      if (stateLayout && site) {
        auto target = stateLayout->genericNBAHoldTargets.find(site.getId());
        if (target != stateLayout->genericNBAHoldTargets.end() &&
            *width <= target->second.width &&
            (!holdTarget || *holdTarget == target->second.handle)) {
          holdTarget = target->second.handle;
          fixedHold = true;
        }
      }
      bool genericHold =
          !driverDestination && !op.getClockingOutputAttr() && !op.getDelay() &&
          holdTarget && stateLayout &&
          talos_rt_stable_handle_decode(*holdTarget, &destination) &&
          destination.kind == TALOS_RT_STABLE_HANDLE_STATIC &&
          (fixedHold ||
           stateLayout->genericNBAHoldRoots.contains(destination.id));
      bool staticallyStaged =
          !op.getClockingOutputAttr() && !driverDestination &&
          staticSitesEnabled && mappedSite &&
          (staticPlan->mergeSafeRoots[rootIndex] || orderedEvalQueue) &&
          adaptor.getDelay().empty() && !site.getTiming() &&
          site.getStorage() != schedule::ComputeNBAStorageKind::DynamicFrontier;
      // A statically staged site keeps its operands on the typed stage.
      SmallVector<Value> arguments;
      if (!staticallyStaged) {
        arguments = {runtimeContext,
                     valuePlane,
                     unknownPlane,
                     llvmConstant(rewriter, location, i64, stateBitCount),
                     adaptor.getDestination().front(),
                     llvmConstant(rewriter, location, i64, *width),
                     delay,
                     value,
                     unknown};
        if (auto clockingOutput = op.getClockingOutputAttr())
          arguments.push_back(
              llvmConstant(rewriter, location, i64,
                           clockingOutput.getValue().getZExtValue()));
      }
      Block *continuation = nullptr;
      // A held-value comparison does not stage an accumulator. In forced
      // FIFO eval a bounded packed aggregate can compare its complete value
      // and unknown planes and reuse the same pending-root view as a scalar.
      // A previous overlapping enqueue still forces capture (4.6(b), 10.4.2).
      ModuleOp module = op->getParentOfType<ModuleOp>();
      uint64_t comparisonBits =
          schedule::has<schedule::Field::ForceGenericNBA>(module) &&
                  schedule::has<schedule::Field::EvalRuntimeCalendar>(module)
              ? 4096
              : TALOS_RT_GENERATED_NBA_MAX_BITS;
      const auto *bound = genericHold && *width <= comparisonBits &&
                                  destination.offset >= 0
                              ? stateLayout->findBound(destination.id)
                              : nullptr;
      auto capturedType =
          dyn_cast<IntegerType>(adaptor.getValue().front().getType());
      if (bound && uint64_t(destination.offset) <= bound->width &&
          *width <= bound->width - uint64_t(destination.offset) &&
          capturedType && capturedType.getWidth() >= *width) {
        Value captured = adaptor.getValue().front();
        Value x;
        // A promoted leaf in a four-state design still compares CURRENT's
        // unknown bits. Only a two-state model has no unknown plane at all.
        if (!native::has<native::TwoState>(op->getParentOfType<ModuleOp>()))
          x = adaptor.getValue().size() == 2
                  ? adaptor.getValue()[1]
                  : llvmConstant(rewriter, location, captured.getType(), 0);
        Value diff = buildGeneratedNBAChange(rewriter, location,
                                             bound->offset + destination.offset,
                                             *width, captured, x);
        Value changed = arith::CmpIOp::create(
            rewriter, location, arith::CmpIPredicate::ne, diff,
            llvmConstant(rewriter, location, diff.getType(), 0));
        // A captured view may still be an SSA argument during conversion.
        // Only use its source proof when this execution produced that handle.
        if (!destinationValue)
          changed = arith::OrIOp::create(
              rewriter, location, changed,
              arith::CmpIOp::create(
                  rewriter, location, arith::CmpIPredicate::ne,
                  adaptor.getDestination().front(),
                  llvmConstant(rewriter, location, i64, *holdTarget)));
        Block *head = op->getBlock();
        continuation = rewriter.splitBlock(head, Block::iterator(op));
        auto *region = head->getParent();
        Block *check =
            rewriter.createBlock(region, continuation->getIterator());
        Block *stage =
            rewriter.createBlock(region, continuation->getIterator());
        rewriter.setInsertionPointToEnd(head);
        cf::CondBranchOp::create(rewriter, location, changed, stage, check);
        rewriter.setInsertionPointToEnd(check);
        Value pending =
            LLVM::CallOp::create(
                rewriter, location, TypeRange{i32},
                SymbolRefAttr::get(rewriter.getContext(),
                                   "talos_rt_v1_scheduler_generic_nba_pending"),
                ValueRange{runtimeContext, llvmConstant(rewriter, location, i32,
                                                        destination.id)})
                .getResult();
        cf::CondBranchOp::create(
            rewriter, location,
            arith::CmpIOp::create(rewriter, location, arith::CmpIPredicate::ne,
                                  pending,
                                  llvmConstant(rewriter, location, i32, 0)),
            stage, continuation);
        rewriter.setInsertionPointToEnd(stage);
        genericHold = false;
      } else if (!destinationValue)
        genericHold = false;
      bool scalarFIFO =
          schedule::has<schedule::Field::ForceGenericNBA>(module) &&
          schedule::has<schedule::Field::EvalRuntimeCalendar>(module) &&
          !staticallyStaged && !genericHold && !driverDestination &&
          !op.getClockingOutputAttr() && !op.getDelay() && *width <= 64 &&
          capturedType && capturedType.getWidth() <= 64;
      if (scalarFIFO) {
        auto word = [&](Value plane) {
          return resizeNativeInteger(rewriter, location, plane,
                                     rewriter.getI64Type());
        };
        Value x = adaptor.getValue().size() == 2
                      ? word(adaptor.getValue()[1])
                      : llvmConstant(rewriter, location, i64, 0);
        LLVM::CallOp::create(
            rewriter, location, TypeRange{}, "talos_rt_v1_scheduler_nba_scalar",
            ValueRange{runtimeContext, valuePlane, unknownPlane, arguments[3],
                       adaptor.getDestination().front(), arguments[5],
                       word(adaptor.getValue().front()), x});
      } else if (staticallyStaged) {
        // A static site's stage stays typed until AOT materialization
        // chooses its route (IEEE 1800-2023 4.9.4, 10.4.2).
        schedule::NativeNBAStageOp::create(
            rewriter, location, runtimeContext,
            adaptor.getDestination().front(), value,
            adaptor.getValue().size() == 2 ? unknown : Value(), site.getId(),
            stateBitCount, *width, rootIndex);
      } else {
        Value status =
            LLVM::CallOp::create(
                rewriter, location, TypeRange{i32},
                SymbolRefAttr::get(
                    rewriter.getContext(),
                    op.getClockingOutputAttr()
                        ? driverDestination
                              ? "talos_rt_v1_scheduler_clocking_driver_nba"
                              : "talos_rt_v1_scheduler_clocking_nba"
                    : driverDestination ? "talos_rt_v1_scheduler_driver_nba"
                    : genericHold       ? "talos_rt_v1_scheduler_nba_if_changed"
                                        : "talos_rt_v1_scheduler_nba"),
                arguments)
                .getResult();
        if (mappedSite)
          schedule::set<schedule::Field::EvalPendingRuntimeRoot>(
              status.getDefiningOp(), rewriter.getI32IntegerAttr(rootIndex));
        LLVM::CallOp::create(rewriter, location, TypeRange{},
                             SymbolRefAttr::get(rewriter.getContext(),
                                                "talos_rt_v1_scheduler_fail"),
                             ValueRange{runtimeContext, status});
      }
      if (continuation) {
        cf::BranchOp::create(rewriter, location, continuation);
        rewriter.setInsertionPoint(op);
      }
    }
    rewriter.eraseOp(op);
    return success();
  }

private:
  uint64_t stateBitCount;
  const NativeStaticNBAPlan *staticPlan;
  const NativeStateLayout *stateLayout;
  bool staticSitesEnabled;
  bool guardedClaims;
};

} // namespace

void emitGeneratedNBATransient(OpBuilder &builder, Location location,
                               Value accumulator, uint64_t word, Value mask,
                               Value newValue, Value newUnknown, Value staged) {
  Type i64 = builder.getI64Type();
  uint64_t offset = word * sizeof(uint64_t);
  auto load = [&](NBAField field) -> Value {
    return schedule::NativeNBAAccumulatorLoadOp::create(
        builder, location, i64, accumulator, field, offset, 8);
  };
  if (!staged)
    staged = arith::AndIOp::create(builder, location, load(NBAField::WriteMask),
                                   mask);
  Value differs = arith::OrIOp::create(
      builder, location,
      arith::XOrIOp::create(builder, location, load(NBAField::Value), newValue),
      arith::XOrIOp::create(builder, location, load(NBAField::Unknown),
                            newUnknown));
  Value transient = load(NBAField::Transient);
  schedule::NativeNBAAccumulatorStoreOp::create(
      builder, location,
      arith::OrIOp::create(
          builder, location, transient,
          arith::AndIOp::create(builder, location, staged, differs)),
      accumulator, NBAField::Transient, offset, 8);
}

Value buildNativeNBAChange(OpBuilder &builder, Location location,
                           uint64_t bitOffset, unsigned width, Value value,
                           Value unknown) {
  return buildGeneratedNBAChange(builder, location, bitOffset, width, value,
                                 unknown);
}

void populateNBAToLLVMConversionPatterns(
    RewritePatternSet &patterns, TypeConverter &converter,
    uint64_t stateBitCount, const NativeStaticNBAPlan *staticPlan,
    const NativeStateLayout *stateLayout, bool staticSitesEnabled,
    bool guardedClaims, bool evalCeiling,
    const DenseSet<Operation *> &completePackedSliceNBAs) {
  patterns.add<PowerCancelNBAConversion>(converter, patterns.getContext());
  patterns.add<PowerNBAConversion>(converter, patterns.getContext(),
                                   stateBitCount);
  patterns.add<PowerNBAViewConversion>(converter, patterns.getContext(),
                                       stateBitCount);
  patterns.add<InertialDriverConversion>(converter, patterns.getContext(),
                                         stateBitCount);
  patterns.add<InertialPathDriverConversion>(converter, patterns.getContext(),
                                             stateBitCount);
  patterns.add<InertialPathStorageConversion>(converter, patterns.getContext(),
                                              stateBitCount);
  patterns.add<InertialStrengthPairConversion>(converter, patterns.getContext(),
                                               stateBitCount);
  patterns.add<InertialPathStrengthPairConversion>(
      converter, patterns.getContext(), stateBitCount);
  patterns.add<PackedSliceNBAConversion>(
      converter, patterns.getContext(), stateBitCount, staticPlan, stateLayout,
      staticSitesEnabled, guardedClaims, completePackedSliceNBAs);
  patterns.add<ImmediateNBAConversion>(converter, patterns.getContext(),
                                       stateBitCount, staticPlan, stateLayout,
                                       staticSitesEnabled, guardedClaims);
}

void lowerNativeNBAStages(ModuleOp module) {
  SmallVector<schedule::NativeNBAStageOp> stages;
  module.walk(
      [&](schedule::NativeNBAStageOp stage) { stages.push_back(stage); });
  for (schedule::NativeNBAStageOp stage : stages) {
    OpBuilder builder(stage);
    Location location = stage.getLoc();
    Type i32 = builder.getI32Type(), i64 = builder.getI64Type();
    auto pointer = LLVM::LLVMPointerType::get(builder.getContext());
    // The runtime reads the unknown planes only for a value with X/Z bits.
    Value unknown = stage.getUnknown();
    Value unknownPlane =
        unknown ? detail::createStatePlaneAddress(builder, location,
                                                  schedule::StatePlane::Unknown)
                : LLVM::ZeroOp::create(builder, location, pointer).getResult();
    if (!unknown)
      unknown = LLVM::ZeroOp::create(builder, location, pointer);
    auto status = LLVM::CallOp::create(
        builder, location, TypeRange{i32},
        SymbolRefAttr::get(builder.getContext(),
                           "talos_rt_v1_scheduler_static_nba"),
        ValueRange{stage.getRuntimeContext(),
                   llvmConstant(builder, location, i64, stage.getSite()),
                   detail::createStatePlaneAddress(builder, location,
                                                   schedule::StatePlane::Value),
                   unknownPlane,
                   llvmConstant(builder, location, i64, stage.getStateBits()),
                   stage.getHandle(),
                   llvmConstant(builder, location, i64, stage.getWidth()),
                   stage.getValue(), unknown});
    schedule::set<schedule::Field::EvalPendingRuntimeRoot>(
        status, builder.getI32IntegerAttr(stage.getRoot()));
    LLVM::CallOp::create(
        builder, location, TypeRange{},
        SymbolRefAttr::get(builder.getContext(), "talos_rt_v1_scheduler_fail"),
        ValueRange{stage.getRuntimeContext(), status.getResult()});
    stage.erase();
  }
}

} // namespace talos::detail
