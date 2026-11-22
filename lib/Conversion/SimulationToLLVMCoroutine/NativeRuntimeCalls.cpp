//===- NativeRuntimeCalls.cpp - Effects of native runtime calls -----------===//

#include "NativeRuntimeCalls.h"

#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

namespace talos::detail {
using namespace native_runtime;

bool hasNativeRuntimeEffect(mlir::Operation *op, Effect effect) {
  if (auto call = llvm::dyn_cast<mlir::LLVM::CallOp>(op)) {
    std::optional<llvm::StringRef> callee = call.getCallee();
    return callee && hasNativeRuntimeEffect(*callee, effect);
  }
  // A static NBA stage the runtime keeps lowers to the static NBA entry and
  // the failure check of its status.
  if (llvm::isa<schedule::NativeNBAStageOp>(op))
    return (getNativeRuntimeEffects(NativeRuntimeEntry::SchedulerStaticNba) &
            getNativeRuntimeEffects(NativeRuntimeEntry::SchedulerFail) &
            effect) == effect;
  // A stable-handle offset is the runtime's handle arithmetic.
  if (llvm::isa<schedule::NativeHandleOffsetOp>(op))
    return (getNativeRuntimeEffects(NativeRuntimeEntry::NativeHandleOffset) &
            effect) == effect;
  // A handle-addressed state access is the call of its runtime entry.
  if (isNativeStateHandleAccess(op))
    return (getNativeRuntimeEffects(getNativeStateHandleAccessEntry(op)) &
            effect) == effect;
  // A handle-addressed transition is the runtime's signal transition until
  // the eval plan publishes it itself.
  if (isNativeHandleTransition(op))
    return (getNativeRuntimeEffects(
                NativeRuntimeEntry::SchedulerSignalTransition) &
            effect) == effect;
  return false;
}

bool callsNativeRuntime(mlir::Operation *op, NativeRuntimeEntry entry) {
  auto call = llvm::dyn_cast_if_present<mlir::LLVM::CallOp>(op);
  return call && call.getCallee() == getNativeRuntimeSymbol(entry);
}

} // namespace talos::detail
