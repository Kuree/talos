//===- NativeMethodEligibilityAnalysisTestPass.cpp - Inspect methods -----===//

#include "AnalysisTestPasses.h"
#include "talos/Analysis/NativeMethodEligibilityAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace {
class NativeMethodEligibilityAnalysisTestPass
    : public PassWrapper<NativeMethodEligibilityAnalysisTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(
      NativeMethodEligibilityAnalysisTestPass)
  StringRef getArgument() const final {
    return "test-talos-native-method-eligibility";
  }
  StringRef getDescription() const final {
    return "inspect synchronous native function and task closures";
  }
  void runOnOperation() final {
    auto module = getOperation();
    module.walk([&](talos::sim::SimDesignOp design) {
      talos::analysis::NativeMethodEligibilityAnalysis eligibility(design);
      llvm::errs() << "native-method-graph @" << design.getSymName()
                   << " functions=" << eligibility.getNumFunctions()
                   << " families=" << eligibility.getNumVirtualFamilies()
                   << " edges=" << eligibility.getNumCallEdges() << '\n';
      if (auto limit = module->getAttrOfType<IntegerAttr>(
              "test.native_method_edge_limit"))
        if (eligibility.getNumCallEdges() > limit.getValue().getZExtValue()) {
          module.emitError("native method graph exceeded shared-family budget");
          signalPassFailure();
        }
      for (auto method : design.getOps<talos::sim::SimClassMethodDeclOp>()) {
        if (!method.getImplementation())
          continue;
        llvm::errs() << "native-method @" << method.getSymName()
                     << " task=" << method.getIsTask() << " eligible="
                     << eligibility.canInvoke(*method.getImplementation())
                     << '\n';
        if (method.getIsVirtual())
          llvm::errs() << "native-family " << *method.getSignatureId()
                       << " task=" << method.getIsTask() << " eligible="
                       << eligibility.canInvokeVirtual(*method.getSignatureId(),
                                                       method.getIsTask())
                       << '\n';
      }
    });
    markAllAnalysesPreserved();
  }
};
} // namespace

namespace talos {
void registerNativeMethodEligibilityAnalysisTestPass() {
  PassRegistration<NativeMethodEligibilityAnalysisTestPass>();
}
} // namespace talos
