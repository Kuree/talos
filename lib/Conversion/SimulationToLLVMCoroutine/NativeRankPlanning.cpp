//===- NativeRankPlanning.cpp - Native eval ranking ===//
#include "NativeRankPlanning.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Runtime/ActivationOrder.h"
#include <chrono>

namespace talos::detail {
namespace {
using analysis::NativeRankStrategy;
// The final raw-call and forwarding certificates depend on transformations
// inside native process materialization. Keep that real lowering as the
// incumbent. Only a strictly better order incurs a second process lowering;
// the frontend, final LLVM pipeline and code generator are never replayed.
class RankNativeProcessesPass final
    : public mlir::PassWrapper<RankNativeProcessesPass,
                               mlir::OperationPass<mlir::ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RankNativeProcessesPass)
  RankNativeProcessesPass() = default;
  RankNativeProcessesPass(const RankNativeProcessesPass &other)
      : PassWrapper(other) {}
  RankNativeProcessesPass(NativeRankStrategy policy, bool words,
                          bool aggregates) {
    strategy = policy;
    nativeWords = words;
    nativeAggregates = aggregates;
  }
  llvm::StringRef getArgument() const final {
    return "schedule-rank-native-processes";
  }
  llvm::StringRef getDescription() const final {
    return "Plan and materialize native processes using the selected rank "
           "analysis";
  }
  void getDependentDialects(mlir::DialectRegistry &registry) const final {
    mlir::OpPassManager pm("builtin.module");
    buildNativeProcesses(pm, nativeWords, nativeAggregates);
    pm.getDependentDialects(registry);
  }

private:
  Option<NativeRankStrategy> strategy{
      *this, "native-rank", llvm::cl::desc("Native evaluator rank analysis"),
      nativeRankStrategyValues(),
      llvm::cl::init(NativeRankStrategy::Heuristic)};
  Option<bool> nativeWords{*this, "native-words", llvm::cl::init(true)};
  Option<bool> nativeAggregates{*this, "native-aggregates",
                                llvm::cl::init(true)};
  void exchangeModules(mlir::ModuleOp a, mlir::ModuleOp b) {
    getAnalysisManager().clear();
    auto attrs = a->getAttrDictionary();
    a->setAttrs(b->getAttrDictionary());
    b->setAttrs(attrs);
    mlir::Region saved;
    saved.takeBody(a.getBodyRegion());
    a.getBodyRegion().takeBody(b.getBodyRegion());
    b.getBodyRegion().takeBody(saved);
  }
  void runOnOperation() override {
    auto module = getOperation();
    auto lower = [&](NativeRankTrial *trial) {
      mlir::OpPassManager pm("builtin.module");
      buildNativeProcesses(pm, nativeWords, nativeAggregates, trial);
      return runPipeline(pm, module);
    };
    if (strategy == NativeRankStrategy::Heuristic) {
      if (failed(lower(nullptr)))
        signalPassFailure();
      return;
    }
    if (!analysis::hasZ3NativeRankAnalysis()) {
      module.emitError("native rank strategy 'z3' requires TALOS_ENABLE_Z3");
      return signalPassFailure();
    }
    auto scheduler = schedule::get<schedule::Field::NativeScheduler>(module);
    if (scheduler &&
        (scheduler.getValue() == schedule::NativeSchedulerMode::Generic ||
         scheduler.getValue() == schedule::NativeSchedulerMode::AOT)) {
      if (failed(lower(nullptr)))
        signalPassFailure();
      return;
    }
    mlir::OwningOpRef<mlir::ModuleOp> saved(module.clone());
    NativeRankTrial baseline;
    if (failed(lower(&baseline)))
      return signalPassFailure();
    if (!baseline.encountered || baseline.layout.helpers.empty())
      return;
    runtime::ActivationOrder order;
    const auto start = std::chrono::steady_clock::now();
    auto result = analysis::NativeEvalRankAnalysis::get(strategy).analyze(
        baseline.graph, baseline.layout, order);
    if (!result) {
      module.emitError() << llvm::toString(result.takeError());
      return signalPassFailure();
    }
    const auto elapsed =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - start)
            .count();
    bool improved = result->selected < result->original;
    if (improved) {
      exchangeModules(module, *saved);
      NativeRankTrial candidate;
      candidate.expected = &baseline.graph;
      candidate.selected = order.nodes;
      std::string diagnostic;
      bool lowered;
      {
        mlir::ScopedDiagnosticHandler trialDiagnostics(
            module.getContext(), [&](mlir::Diagnostic &message) {
              if (diagnostic.empty() &&
                  message.getSeverity() == mlir::DiagnosticSeverity::Error)
                diagnostic = message.str();
              return mlir::success();
            });
        lowered = succeeded(lower(&candidate));
      }
      if (!lowered || !candidate.encountered || !candidate.matches ||
          !candidate.layout.preserves(baseline.layout)) {
        exchangeModules(module, *saved);
        improved = false;
        if (!lowered)
          module.emitWarning() << "retaining heuristic native ranks after "
                                  "candidate lowering failed: "
                               << diagnostic;
      }
    }
    if (native::has<native::DebugTiming>(module)) {
      auto cost = improved ? result->selected : result->original;
      llvm::errs() << "talos native rank: strategy=z3 heuristic="
                   << result->original.first << "," << result->original.second
                   << " selected=" << cost.first << "," << cost.second
                   << " solver=" << (result->proven ? "optimal" : "bounded")
                   << " analysis_seconds=" << elapsed << " lowering="
                   << (improved                              ? "accepted"
                       : result->selected < result->original ? "restored"
                                                             : "unchanged")
                   << "\n";
    }
  }
};
} // namespace
std::unique_ptr<mlir::Pass>
createRankNativeProcessesPass(NativeRankStrategy strategy, bool words,
                              bool aggregates) {
  return std::make_unique<RankNativeProcessesPass>(strategy, words, aggregates);
}
void registerNativeRankPlanningPass() {
  mlir::PassRegistration<RankNativeProcessesPass>();
}
} // namespace talos::detail
