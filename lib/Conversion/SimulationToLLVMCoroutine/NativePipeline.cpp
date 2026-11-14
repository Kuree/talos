#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Pass/PassManager.h"
#include "talos/Conversion/Passes.h"
#include "talos/Conversion/SimulationToLLVMCoroutine.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
namespace talos {
void buildSimulationToLLVMCoroutinePipeline(mlir::OpPassManager &manager,
                                            bool nativeWords,
                                            bool nativeAggregates) {
  // Bytecode and the actor CFG stay canonical. Lower address selections only
  // in their borrowed invocation bodies, before native storage admission.
  SpecializeReferenceJoinsPassOptions joins;
  joins.nativeBodiesOnly = true;
  manager.nest<sim::SimDesignOp>().nest<sim::SimFuncOp>().addPass(
      createSpecializeReferenceJoinsPass(joins));
  manager.nest<sim::SimFuncOp>().addPass(
      createSpecializeReferenceJoinsPass(joins));
  LowerConditionalReferenceAccessesPassOptions reads;
  reads.nativeBodiesOnly = true;
  manager.nest<sim::SimDesignOp>().nest<sim::SimFuncOp>().addPass(
      createLowerConditionalReferenceAccessesPass(reads));
  manager.nest<sim::SimFuncOp>().addPass(
      createLowerConditionalReferenceAccessesPass(reads));
  manager.addPass(createPrepareNativeScheduleInputsPass());
  manager.addPass(createPlanNativeStatePass());
  manager.addPass(createPrepareNativeProcessFramesPass());
  manager.addPass(createPlanNativeTransfersPass());
  manager.addPass(createShareNativeTransfersPass());
  manager.addPass(createPlanNativeActorsPass());
  manager.addPass(createSpecializeNativeCapturesPass());
  manager.addPass(createPlanNativeSchedulePass());
  manager.addPass(createPrepareNativeManagedRootsPass());
  manager.addPass(createMarkCleanNativeNBAPass());
  manager.addPass(createSpecializeNativeEvalPass());
  if (nativeAggregates)
    manager.addPass(createPrepareNativeAggregatesPass());
  if (nativeWords)
    manager.addPass(createOptimizeNativeWordsPass());
  manager.addPass(createLowerNativeWordRegionsPass());
  // Two-state copies consume the final eval bodies and their native word
  // regions; bytecode stays canonical. Whole activations are versioned first;
  // region versioning leaves those activations alone.
  manager.addPass(createVersionKnownActivationsPass());
  manager.addPass(createVersionKnownRegionsPass());
  // Each version forwards its own values: reads of state an activation
  // already wrote or read take that SSA value; the writes stay.
  manager.addPass(createTalosSimForwardActivationStatePass());
  manager.addPass(createPrepareNativeTransferKernelsPass());
  manager.addPass(createAnnotateCompactNativeNBAPass());
  manager.addPass(createPrepareNativeFragmentsPass());
  manager.addPass(createPlanNativeEvalOwnershipPass());
  manager.addPass(createAnnotateCompactNativeNBAPass());
  manager.addPass(createPlanNativeExecutableNodesPass());
  manager.addPass(createResolveNativeEvalSchedulePass());
  manager.addPass(createAdmitNativeStartedOwnersPass());
  manager.addPass(createMaterializeNativeProcessesPass());
  manager.addPass(createThinNativeGCCollectionsPass());
  manager.addPass(createLowerNativeGCCollectionsPass());
  // Clean packed lowering's output where it was produced, one function at a
  // time, so conversion and the module-wide finalization see the reduced IR.
  manager.nest<mlir::func::FuncOp>().addPass(createCleanupNativeFunctionPass());
  manager.addPass(createPrepareNativeLLVMFunctionsPass());
  manager.nest<mlir::LLVM::LLVMFuncOp>().addPass(
      createConvertNativeFunctionBodyPass());
  buildNativeLLVMFinalizationPipeline(manager);
}
void buildNativeLLVMFinalizationPipeline(mlir::OpPassManager &manager) {
  manager.addPass(createFinalizeNativeLLVMWrappersPass());
  // The finalization stages see state accesses as typed operations where the
  // typed operations can express them; the rest, and accesses the stages
  // themselves still emit, stay in LLVM form. The last stage lowers the typed
  // accesses to LLVM memory accesses again.
  manager.nest<mlir::LLVM::LLVMFuncOp>().addPass(
      createRaiseNativeStateAccessPass());
  manager.addPass(createMaterializeNativeEvalRoutesPass());
  manager.addPass(createPublishNativeProofsPass());
  manager.addPass(createMaterializeNativeEvalGroupBodiesPass());
  manager.addPass(createMaterializeNativeEvalTransactionsPass());
  manager.addPass(createFinalizeNativeFunctionsPass());
}
void registerSimulationToLLVMCoroutinePipeline() {
  struct Options : mlir::PassPipelineOptions<Options> {
    Option<bool> nativeWords{
        *this, "native-words",
        llvm::cl::desc("Optimize independent native word lanes"),
        llvm::cl::init(true)};
    Option<bool> nativeAggregates{
        *this, "native-aggregates",
        llvm::cl::desc("Forward proved native SSA array elements"),
        llvm::cl::init(true)};
  };
  mlir::PassPipelineRegistration<Options>(
      "convert-talos-sim-processes-to-llvm-coroutines",
      "Plan, specialize, and lower native simulation processes",
      [](mlir::OpPassManager &manager, const Options &options) {
        buildSimulationToLLVMCoroutinePipeline(manager, options.nativeWords,
                                               options.nativeAggregates);
      });
}
} // namespace talos
