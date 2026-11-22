//===- SimulationToLLVMCoroutine.h - Process coroutine lowering -*- C++ -*-===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVMCOROUTINE_H
#define TALOS_CONVERSION_SIMULATIONTOLLVMCOROUTINE_H

#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Native/NativeRuntimeEntries.h"

#include "mlir/Transforms/DialectConversion.h"

namespace llvm {
class DataLayout;
}

namespace mlir {
class LLVMTypeConverter;
class ModuleOp;
class OpPassManager;
class RewritePatternSet;
class Operation;
class SymbolTableCollection;
namespace LLVM {
class LLVMFuncOp;
} // namespace LLVM
} // namespace mlir

namespace talos::schedule {
class NativeGlobalLookup;
} // namespace talos::schedule

namespace talos {

/// Materialize capture-free, scope-specific bridges for prepared DPI function
/// and task exports before bytecode encoding.
mlir::LogicalResult materializeDPIExportBridges(mlir::ModuleOp module);

/// Append each native planning, specialization and lowering pass in ABI order.
void buildSimulationToLLVMCoroutinePipeline(mlir::OpPassManager &manager,
                                            bool nativeWords = true,
                                            bool nativeAggregates = true);
void registerSimulationToLLVMCoroutinePipeline();
/// Add the native LLVM finalization stages, in order, after
/// convert-native-function-body-to-llvm.
void buildNativeLLVMFinalizationPipeline(mlir::OpPassManager &manager);

/// Lower executable schedule actions after their effect-aware optimization.
/// A caller lowering many functions of one module passes `symbols`, a cache
/// kept coherent with its own symbol changes, so each call does not rebuild
/// the module symbol table.
void materializeNativeScheduleActions(
    mlir::Operation *operation, bool coalesce = true,
    bool preserveReadiness = false,
    mlir::SymbolTableCollection *symbols = nullptr);
/// Materialize actions introduced after the main LLVM conversion, including
/// the integer arithmetic and CFG needed by local readiness regions.
mlir::LogicalResult lowerNativeScheduleActionsToLLVM(
    mlir::Operation *operation, mlir::SymbolTableCollection *symbols = nullptr);
/// How lowerNativeFunctionScheduleActions lowered one function.
struct NativeFunctionActionLowering {
  /// False, before any change, when lowering would add a module symbol (an
  /// unspecialized NBA batch's root table).
  bool lowered = false;
  /// The runtime entry points the lowered actions call, which the caller
  /// declares with declareNativeFunctionActionRuntime.
  bool callsBatchRuntime = false;
  bool callsStaticTransition = false;
};
/// Lower the schedule actions of `function` as lowerNativeScheduleActionsToLLVM
/// does, without changing any other operation, so that several functions can
/// be lowered concurrently. Calls name their runtime entry points, which the
/// caller declares afterwards.
mlir::FailureOr<NativeFunctionActionLowering>
lowerNativeFunctionScheduleActions(mlir::LLVM::LLVMFuncOp function,
                                   const schedule::NativeGlobalLookup &globals);
/// Declare the runtime entry points that a lowering calls, in the order
/// lowerNativeScheduleActionsToLLVM would.
void declareNativeFunctionActionRuntime(
    mlir::ModuleOp module, const NativeFunctionActionLowering &lowering);

/// Lower schedule.handle.offset to the runtime's stable-handle offset, or to
/// the plain sum when proved in bounds, and schedule.handle.guard to a select
/// of the invalid handle. The operations are pure, so first an offset reuses
/// an equal one that dominates it, the folds apply and unused operations go
/// away. The native pipeline calls it inside AOT planning, after the last
/// reader of the typed handle chains, so later passes see only the LLVM form.
void lowerNativeHandleOps(mlir::ModuleOp module);

/// Whether `op` is a handle-addressed state access:
/// schedule.state.load_handle, store_handle, their `_bytes` forms,
/// frame_store or load_automatic.
bool isNativeStateHandleAccess(mlir::Operation *op);
/// The runtime entry a handle-addressed state access stands for.
NativeRuntimeEntry getNativeStateHandleAccessEntry(mlir::Operation *access);

/// Replace a handle-addressed state access by the call of the runtime entry
/// it stands for, on its planes' addresses and the current context (an
/// automatic read names its context). A scalar access passes its value
/// through temporaries it creates; a `_bytes` access passes its buffer.
void lowerNativeStateHandleAccess(mlir::Operation *access);
/// Lower every handle-addressed state access in `module`. The native pipeline
/// calls it inside AOT planning, after the eval bodies' accesses are read, so
/// later passes see only the runtime calls.
void lowerNativeStateHandleAccesses(mlir::ModuleOp module);

/// Whether `op` is a handle-addressed transition:
/// schedule.transition.handle or its `_bytes` form.
bool isNativeHandleTransition(mlir::Operation *op);
/// Replace a handle-addressed transition by the call of the runtime's signal
/// transition on its context, handle, width and plane snapshots: the buffers
/// of a `_bytes` form, temporaries holding the planes of the value form, the
/// null pointer for a missing unknown plane. With the `actor` that executes
/// it, call `entry` instead, the runtime's owned or projected wide
/// publication from that actor.
void lowerNativeHandleTransition(
    mlir::Operation *transition,
    NativeRuntimeEntry entry = NativeRuntimeEntry::SchedulerSignalTransition,
    std::optional<uint32_t> actor = std::nullopt);
/// Lower every handle-addressed transition in `module` to the runtime's
/// signal transition. The native pipeline calls it inside AOT planning, after
/// the eval bodies' transitions are read, so later passes see only the runtime
/// calls.
void lowerNativeHandleTransitions(mlir::ModuleOp module);

/// Address each native state plane through one invariant base per function
/// that accesses it in several blocks, instead of constant offsets from the
/// plane global. Run last, just before translation to LLVM IR.
mlir::LogicalResult addressNativeStateThroughBases(mlir::ModuleOp module);

/// Lower the scheduler main's schedule.lifecycle operations to runtime calls.
/// `startupModules` names the VPI startup libraries, in load order. Run after
/// addressNativeStateThroughBases, just before translation to LLVM IR: the
/// calls take the state planes' and libraries' globals directly.
mlir::LogicalResult
lowerNativeStartupLifecycle(mlir::ModuleOp module,
                            llvm::ArrayRef<std::string> startupModules);

/// Add terminal conversion patterns after the native preparation pipeline.
void populateSimulationCoroutineToLLVMPatterns(
    const mlir::LLVMTypeConverter &converter,
    mlir::RewritePatternSet &patterns);

} // namespace talos

#endif // TALOS_CONVERSION_SIMULATIONTOLLVMCOROUTINE_H
