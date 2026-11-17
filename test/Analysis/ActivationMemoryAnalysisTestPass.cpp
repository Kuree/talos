#include "AnalysisTestPasses.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "talos/Analysis/ActivationControlFlow.h"
#include "talos/Analysis/ActivationIdempotenceAnalysis.h"
#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "talos/Analysis/SSAValueAnalysis.h"
#include "talos/Analysis/SourceMemoryAnalysis.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"
#include <memory>

using namespace mlir;
namespace {
class RepeatableActivationTestPass
    : public PassWrapper<RepeatableActivationTestPass,
                         OperationPass<talos::sim::SimDesignOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RepeatableActivationTestPass)
  StringRef getArgument() const final {
    return "test-talos-repeatable-activations";
  }
  void runOnOperation() final {
    auto design = getOperation();
    talos::analysis::HandleDataflowAnalysis handles(design);
    auto repeatable =
        talos::schedule::collectRepeatableCombinationalActivations(design,
                                                                   handles);
    design.walk([&](talos::sim::SimFuncOp function) {
      llvm::errs() << "repeatable @" << function.getSymName() << " = "
                   << repeatable.contains(function.getSymNameAttr()) << '\n';
    });
    markAllAnalysesPreserved();
  }
};

class SourceMemoryForwardingTestPass
    : public PassWrapper<SourceMemoryForwardingTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SourceMemoryForwardingTestPass)
  StringRef getArgument() const final {
    return "test-talos-source-memory-forwarding";
  }
  StringRef getDescription() const final {
    return "forward loads using dense source-memory snapshots";
  }
  void runOnOperation() final {
    getOperation().walk([&](talos::sim::SimFuncOp function) {
      if (!function.isExternal())
        talos::analysis::forwardSourceMemoryLoads(function, true);
    });
  }
};

class ActivationCanonicalizeTestPass
    : public PassWrapper<ActivationCanonicalizeTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ActivationCanonicalizeTestPass)
  StringRef getArgument() const final {
    return "test-talos-activation-canonicalize";
  }
  StringRef getDescription() const final {
    return "print canonicalized disposable activation CFGs";
  }
  void runOnOperation() final {
    getOperation().walk([&](func::FuncOp function) {
      if (function.isExternal())
        return;
      OwningOpRef<func::FuncOp> copy(cast<func::FuncOp>(function->clone()));
      bool converged =
          succeeded(talos::analysis::canonicalizeActivationControlFlow(*copy));
      llvm::errs() << "canonicalize @" << function.getSymName()
                   << " converged=" << converged << '\n';
      copy->print(llvm::errs());
      llvm::errs() << '\n';
    });
    markAllAnalysesPreserved();
  }
};

class ActivationControlFlowTestPass
    : public PassWrapper<ActivationControlFlowTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ActivationControlFlowTestPass)
  StringRef getArgument() const final {
    return "test-talos-activation-control-flow";
  }
  StringRef getDescription() const final {
    return "print edge-threaded disposable activation CFGs";
  }
  void runOnOperation() final {
    getOperation().walk([&](func::FuncOp function) {
      if (function.isExternal())
        return;
      OwningOpRef<func::FuncOp> copy(cast<func::FuncOp>(function->clone()));
      bool changed = false;
      while (talos::analysis::threadActivationControlFlow(copy->getBody())) {
        changed = true;
        RewritePatternSet patterns(function.getContext());
        for (RegisteredOperationName name :
             function.getContext()->getRegisteredOperations())
          if (name.getDialectNamespace() == "arith" ||
              name.getDialectNamespace() == "cf")
            name.getCanonicalizationPatterns(patterns, function.getContext());
        if (failed(applyPatternsGreedily(*copy, std::move(patterns))) ||
            failed(verify(*copy))) {
          signalPassFailure();
          return;
        }
      }
      llvm::errs() << "control @" << function.getSymName()
                   << " changed=" << changed << '\n';
      copy->print(llvm::errs());
      llvm::errs() << '\n';
    });
    markAllAnalysesPreserved();
  }
};
class RegionValueDependencyTestPass
    : public PassWrapper<RegionValueDependencyTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RegionValueDependencyTestPass)
  StringRef getArgument() const final {
    return "test-talos-region-value-dependencies";
  }
  StringRef getDescription() const final {
    return "print result-specific SSA dependencies through region yields";
  }
  void runOnOperation() final {
    getOperation().walk([&](func::FuncOp function) {
      if (function.isExternal())
        return;
      SmallVector<Value> inputs(function.getArguments());
      Operation *root = function;
      function.walk([&](Operation *op) {
        if (op->hasAttr("test.root"))
          root = op;
      });
      talos::analysis::RegionValueDependencyAnalysis analysis(root, inputs);
      llvm::errs() << "values @" << function.getSymName()
                   << " valid=" << analysis.isValid() << '\n';
      if (!analysis.isValid())
        return;
      function.walk([&](Operation *op) {
        if (!op->hasAttr("test.values"))
          return;
        for (auto [index, result] : llvm::enumerate(op->getResults())) {
          llvm::errs() << "  " << op->getName() << " result " << index << ':';
          for (Value input : analysis.getInputs(result))
            llvm::errs() << " arg" << cast<BlockArgument>(input).getArgNumber();
          llvm::errs() << '\n';
        }
        if (op->getNumResults() == 0) {
          llvm::errs() << "  " << op->getName() << " effect:";
          for (Value input : analysis.getInputs(op))
            llvm::errs() << " arg" << cast<BlockArgument>(input).getArgNumber();
          llvm::errs() << '\n';
        }
      });
    });
    markAllAnalysesPreserved();
  }
};
class ActivationMemoryTestPass
    : public PassWrapper<ActivationMemoryTestPass, OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ActivationMemoryTestPass)
  ActivationMemoryTestPass() = default;
  ActivationMemoryTestPass(const ActivationMemoryTestPass &other)
      : PassWrapper(other) {}
  StringRef getArgument() const final { return "test-talos-activation-memory"; }
  StringRef getDescription() const final {
    return "print source-ordered activation memory facts";
  }
  Option<unsigned> maximumPartitions{*this, "maximum-partitions",
                                     llvm::cl::init(65536)};
  Option<bool> values{*this, "values", llvm::cl::init(false)};
  void runOnOperation() final {
    getOperation().walk([&](talos::sim::SimDesignOp design) {
      talos::analysis::HandleDataflowAnalysis handles(design);
      for (auto function : design.getBody().getOps<talos::sim::SimFuncOp>()) {
        talos::analysis::ActivationMemoryAnalysis memory(
            function, handles, maximumPartitions,
            values ? talos::analysis::ActivationMemoryAnalysis::DependencyMode::
                         ReachingValues
                   : talos::analysis::ActivationMemoryAnalysis::DependencyMode::
                         Accesses);
        llvm::errs() << "activation @" << function.getSymName()
                     << " valid=" << memory.isValid()
                     << " complete=" << memory.hasCompleteWrites() << '\n';
        auto print = [&](StringRef name, auto ranges) {
          llvm::errs() << "  " << name;
          for (auto r : ranges)
            llvm::errs() << " s" << r.root << '[' << r.low << ','
                         << r.low + r.width << ')';
          llvm::errs() << '\n';
        };
        print("live-in", memory.getLiveIns());
        print("must-write", memory.getMustWrites());
        print("may-write", memory.getMayWrites());
        print("repeated", memory.getRepeatedWrites());
        if (values) {
          llvm::errs() << "  values valid=" << memory.hasValueDependencies()
                       << '\n';
          print("value-input", memory.getValueInputs());
          function.walk([&](talos::sim::SimRefStoreOp store) {
            auto found = memory.getPublications().find(store);
            if (found != memory.getPublications().end())
              for (const auto &lane : found->second) {
                llvm::errs() << "  output s" << lane.output.root << '['
                             << lane.output.low << ','
                             << lane.output.low + lane.output.width << ')';
                for (auto input : lane.inputs)
                  llvm::errs() << " s" << input.root << '[' << input.low << ','
                               << input.low + input.width << ')';
                llvm::errs() << '\n';
              }
          });
        }
      }
    });
    markAllAnalysesPreserved();
  }
};
class ActivationRegionTestPass
    : public PassWrapper<ActivationRegionTestPass, OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ActivationRegionTestPass)
  ActivationRegionTestPass() = default;
  ActivationRegionTestPass(const ActivationRegionTestPass &other)
      : PassWrapper(other) {}
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<func::FuncDialect, arith::ArithDialect,
                    cf::ControlFlowDialect, scf::SCFDialect, ub::UBDialect>();
  }
  StringRef getArgument() const final {
    return "test-talos-activation-regions";
  }
  StringRef getDescription() const final {
    return "print activation units and their memory effects";
  }
  Option<bool> dump{*this, "dump", llvm::cl::init(false)};
  Option<bool> verifyPreparedViews{*this, "verify-prepared-views",
                                   llvm::cl::init(false)};
  Option<bool> threadControl{*this, "thread-control", llvm::cl::init(false)};
  Option<bool> canonicalControls{*this, "canonical-controls",
                                 llvm::cl::init(false)};
  Option<bool> publicationFrontiers{*this, "publication-frontiers",
                                    llvm::cl::init(false)};
  Option<bool> publications{*this, "publications", llvm::cl::init(false)};
  Option<bool> regionOrder{*this, "order", llvm::cl::init(false)};
  Option<bool> interleaving{*this, "interleaving", llvm::cl::init(false)};
  Option<bool> rearmInterleaving{*this, "rearm-interleaving",
                                 llvm::cl::init(false)};
  Option<bool> sliceOrder{*this, "slice-order", llvm::cl::init(false)};
  Option<bool> components{*this, "components", llvm::cl::init(false)};
  Option<std::string> sliceCycleFunction{*this, "slice-cycle-function",
                                         llvm::cl::init("")};
  Option<bool> cycleRegions{*this, "cycle-regions", llvm::cl::init(false)};
  Option<bool> reachingValues{*this, "reaching-values", llvm::cl::init(false)};
  Option<bool> inputDependencies{*this, "input-dependencies",
                                 llvm::cl::init(false)};
  Option<bool> inputs{*this, "inputs", llvm::cl::init(false)};
  Option<bool> idempotence{*this, "idempotence", llvm::cl::init(false)};
  Option<bool> compareInputDependencies{
      *this, "compare-input-dependencies",
      llvm::cl::desc("check the input-only dependency proof against full "
                     "publication analysis instead of printing regions"),
      llvm::cl::init(false)};
  Option<unsigned> idempotenceMaximumOperations{
      *this, "idempotence-maximum-operations", llvm::cl::init(500000)};
  Option<int64_t> sliceRoot{*this, "slice-root", llvm::cl::init(-1)};
  ListOption<std::string> functions{*this, "functions",
                                    llvm::cl::CommaSeparated};
  void runOnOperation() final {
    getOperation().walk([&](talos::sim::SimDesignOp design) {
      talos::analysis::HandleDataflowAnalysis handles(design);
      std::optional<talos::analysis::ControlActivationAnalysis> controls;
      if (canonicalControls)
        controls.emplace(design);
      SmallVector<std::unique_ptr<talos::analysis::ActivationRegionAnalysis>>
          owned;
      SmallVector<std::unique_ptr<talos::analysis::ActivationRegionAnalysis>>
          sourceViews;
      for (auto function : design.getBody().getOps<talos::sim::SimFuncOp>()) {
        if (!functions.empty() &&
            !llvm::is_contained(functions, function.getSymName().str()))
          continue;
        if (compareInputDependencies) {
          compare(function, handles);
          continue;
        }
        auto trace =
            [&](talos::analysis::ActivationPreparationOptions::TracePhase phase,
                Operation *view) {
              if (!dump)
                return;
              llvm::errs()
                  << "activation "
                  << (phase == talos::analysis::ActivationPreparationOptions::
                                   TracePhase::Initial
                          ? "initial"
                          : "resume")
                  << " @" << function.getSymName() << '\n';
              view->print(llvm::errs());
              llvm::errs() << '\n';
            };
        talos::analysis::ActivationPreparationOptions preparation;
        preparation.trace = trace;
        if (threadControl)
          preparation.controlFlow = talos::analysis::
              ActivationPreparationOptions::ControlFlow::ThreadDispatch;
        preparation.controls = controls ? &*controls : nullptr;
        auto prepared =
            talos::analysis::prepareActivation(function, preparation);
        std::string preparedText = snapshot(prepared.getFunction());
        auto proof =
            std::make_unique<talos::analysis::ActivationRegionAnalysis>(
                std::move(prepared), handles,
                inputDependencies ? talos::analysis::ActivationMemoryAnalysis::
                                        DependencyMode::Inputs
                : reachingValues  ? talos::analysis::ActivationMemoryAnalysis::
                                        DependencyMode::ReachingValues
                                  : talos::analysis::ActivationMemoryAnalysis::
                                        DependencyMode::Accesses);
        verifySnapshot(proof->getActivationFunction(), preparedText);
        if (publicationFrontiers) {
          auto frontierTrace = [&](StringRef reason, Value value) {
            if (dump) {
              llvm::errs() << "frontier @" << function.getSymName()
                           << " retained: " << reason << ' ';
              if (value)
                value.print(llvm::errs());
              llvm::errs() << '\n';
            }
          };
          auto view = talos::analysis::prepareActivationFrontiers(
              *proof, handles, frontierTrace);
          std::unique_ptr<talos::analysis::ActivationRegionAnalysis> refined;
          if (view) {
            std::string frontierText = snapshot(view->getFunction());
            refined =
                std::make_unique<talos::analysis::ActivationRegionAnalysis>(
                    std::move(*view), handles, proof->getDependencyMode());
            verifySnapshot(refined->getActivationFunction(), frontierText);
            if (!refined->isValid())
              refined.reset();
          }
          if (refined) {
            // Keep source views alive: the refined analysis retains their
            // identity, just as the production interleaving cache does.
            sourceViews.push_back(std::move(proof));
            proof = std::move(refined);
          }
        }
        auto &analysis = *proof;
        if (auto maximum = function->getAttrOfType<IntegerAttr>(
                "test.activation_max_value_nodes")) {
          const auto &memory = analysis.getMemory();
          if (!memory.hasInputDependencies() ||
              memory.getValueNodeCount() > maximum.getInt()) {
            function.emitError(
                "activation value graph exceeded its node budget: ")
                << memory.getValueNodeCount() << " ("
                << memory.getDependencyFailure() << ')';
            signalPassFailure();
          }
        }
        llvm::errs() << "regions @" << function.getSymName()
                     << " valid=" << analysis.isValid();
        if (!analysis.isValid())
          llvm::errs() << " reason="
                       << talos::analysis::stringifyActivationFailure(
                              analysis.getFailureReason());
        llvm::errs() << '\n';
        if (idempotence && analysis.isValid())
          llvm::errs() << "  idempotent="
                       << talos::analysis::hasIdempotentStateTransition(
                              analysis.getActivationFunction(),
                              analysis.getMemory(), handles,
                              idempotenceMaximumOperations)
                       << '\n';
        if (idempotence && reachingValues && analysis.isValid())
          llvm::errs() << "  final-state-idempotent="
                       << analysis.getMemory().hasIdempotentFinalState()
                       << '\n';
        if (inputs) {
          const auto &memory = analysis.getMemory();
          auto print = [&](StringRef label, auto ranges) {
            llvm::errs() << "  " << label;
            for (auto range : ranges)
              llvm::errs() << " s" << range.root << '[' << range.low << ','
                           << range.low + range.width << ')';
            llvm::errs() << '\n';
          };
          print("live-in", memory.getLiveIns());
          llvm::errs() << "  values valid=" << memory.hasValueDependencies()
                       << '\n';
          if (reachingValues && !memory.hasValueDependencies())
            llvm::errs() << "  value reason=" << memory.getDependencyFailure()
                         << '\n';
          if (inputDependencies)
            llvm::errs() << "  inputs valid=" << memory.hasInputDependencies()
                         << '\n';
          if (inputDependencies && !memory.hasInputDependencies())
            llvm::errs() << "  input reason=" << memory.getDependencyFailure()
                         << '\n';
          print("value-input", memory.getValueInputs());
          print("final-input", memory.getFinalInputs());
          print("final-state-input", memory.getFinalStateInputs());
          print("must-write", memory.getMustWrites());
          print("may-write", memory.getMayWrites());
        }
        for (const auto &node : analysis.getNodes()) {
          if (node.reads.empty() && node.writes.empty())
            continue;
          llvm::errs() << "  node " << node.operation->getName();
          auto print = [&](StringRef name, auto ranges) {
            for (auto range : ranges)
              llvm::errs() << ' ' << name << ":s" << range.root << '['
                           << range.low << ',' << range.low + range.width
                           << ')';
          };
          print("read", node.reads);
          print("write", node.writes);
          llvm::errs() << '\n';
        }
        if (dump && analysis.isValid())
          analysis.getActivationFunction().print(llvm::errs());
        if (sliceRoot >= 0 && analysis.isValid()) {
          talos::analysis::ActivationSlice slice{&analysis, {}, {}};
          analysis.getActivationFunction().walk([&](Operation *op) {
            auto found = analysis.getMemory().getWrites().find(op);
            if (found != analysis.getMemory().getWrites().end() &&
                llvm::any_of(found->second, [&](auto range) {
                  return range.root == uint64_t(sliceRoot);
                }))
              slice.stores.push_back(op);
          });
          if (!slice.stores.empty())
            if (auto view = talos::analysis::cloneActivationSlice(slice)) {
              llvm::errs() << "activation slice @" << function.getSymName()
                           << '\n';
              view->print(llvm::errs());
              llvm::errs() << '\n';
            }
        }
        if (publications && analysis.isValid()) {
          auto values = talos::analysis::getActivationPublications(analysis);
          if (values)
            for (const auto &publication : *values) {
              llvm::errs() << "  publication";
              auto print = [&](StringRef kind, auto ranges) {
                for (auto range : ranges)
                  llvm::errs()
                      << ' ' << kind << ":s" << range.root << '[' << range.low
                      << ',' << range.low + range.width << ')';
              };
              print("read", publication.reads);
              print("write", publication.writes);
              llvm::errs() << '\n';
            }
        }
        if (publications || regionOrder || interleaving || rearmInterleaving ||
            sliceOrder || components)
          owned.push_back(std::move(proof));
      }
      if (publications || regionOrder || interleaving || rearmInterleaving ||
          sliceOrder || components) {
        SmallVector<const talos::analysis::ActivationRegionAnalysis *> views;
        for (const auto &view : owned)
          views.push_back(view.get());
        SmallVector<talos::analysis::ActivationRegionStep> cycle;
        if (rearmInterleaving) {
          auto cohorts = talos::analysis::getActivationPulseComponents(views);
          llvm::errs() << "rearm interleaving: components=" << cohorts.size()
                       << '\n';
          for (const auto &cohort : cohorts) {
            auto trace = [&](const auto *activation, Value value,
                             StringRef reason) {
              if (!dump)
                return;
              llvm::errs() << "pulse @"
                           << activation->getActivationFunction().getSymName()
                           << ": " << reason << ' ';
              value.print(llvm::errs());
              llvm::errs() << '\n';
            };
            auto plan = talos::analysis::getActivationRearmPlan(cohort, trace);
            llvm::errs() << "  rearm plan: ";
            if (!plan)
              llvm::errs() << "unavailable";
            else if (plan->preemptions.empty())
              llvm::errs() << "unchanged";
            else {
              llvm::errs() << "handoffs=" << plan->minimumHandoffs
                           << " preemptions=";
              for (auto *activation : plan->preemptions)
                llvm::errs()
                    << " @" << activation->getActivationFunction().getSymName();
            }
            llvm::errs() << '\n';
          }
        }
        if (interleaving) {
          talos::analysis::ActivationInterleavingPreparation preparation(
              handles);
          SmallVector<std::pair<Operation *, std::string>> snapshots;
          auto remember = [&](const auto *view) {
            if (view && view->getActivationFunction()) {
              Operation *operation = view->getActivationFunction();
              snapshots.emplace_back(operation, snapshot(operation));
            }
          };
          for (const auto *view : views)
            remember(view);
          preparation.prepare(views);
          for (const auto *view : views)
            remember(preparation.getFrontierView(view));
          talos::analysis::ActivationInterleavingAnalysis analysis(preparation);
          for (unsigned query = 0; query != 2; ++query) {
            auto order = analysis.getOrder(views, &cycle);
            for (const auto &[operation, before] : snapshots)
              verifySnapshot(operation, before);
            bool preserved = true;
            if (!analysis.hasProvenLivelock()) {
              auto original = talos::analysis::getActivationRegionOrder(views);
              preserved = bool(order) == bool(original);
              if (order && original)
                preserved &= llvm::equal(
                    *order, *original, [](const auto &a, const auto &b) {
                      return a.activation == b.activation &&
                             a.operation == b.operation;
                    });
              if (!preserved) {
                design.emitError("non-livelocking interleaving changed");
                signalPassFailure();
              }
            }
            llvm::errs() << "interleaving order: "
                         << (order           ? "acyclic"
                             : cycle.empty() ? "unavailable"
                                             : "cyclic")
                         << " refined=" << analysis.getRefinedActivationCount()
                         << " livelock-witness=" << analysis.hasProvenLivelock()
                         << " preserved=";
            if (analysis.hasProvenLivelock())
              llvm::errs() << "n/a";
            else
              llvm::errs() << preserved;
            llvm::errs() << " handoffs=";
            if (auto handoffs = analysis.getMinimumHandoffs())
              llvm::errs() << *handoffs;
            else
              llvm::errs() << "unavailable";
            llvm::errs() << " frontiers="
                         << analysis.getFrontierActivationCount() << '\n';
            if (dump && order) {
              llvm::errs() << "interleaving runs:";
              const talos::analysis::ActivationRegionAnalysis *last = nullptr;
              for (const auto &step : *order) {
                const auto *owner = step.activation->getSourceActivation();
                if (owner != last)
                  llvm::errs()
                      << " @" << owner->getActivationFunction().getSymName();
                last = owner;
              }
              llvm::errs() << '\n';
            }
          }
        }
        if (components) {
          auto print = [&](StringRef kind, const auto &schedule) {
            llvm::errs() << kind << " components: ";
            if (!schedule) {
              llvm::errs() << "unsupported\n";
              return;
            }
            llvm::errs() << "valid nodes=" << schedule->nodes.size()
                         << " components=" << schedule->cyclic.size()
                         << " cyclic=" << llvm::count(schedule->cyclic, true)
                         << " events=" << schedule->sensitivityEvents.size()
                         << '\n';
            using Kind = talos::analysis::ActivationSchedule::DependencyKind;
            for (auto [name, kind] : {std::pair{"source", Kind::SourceOrder},
                                      {"ssa", Kind::SSA},
                                      {"snapshot", Kind::Snapshot}})
              llvm::errs() << "  " << name << '='
                           << llvm::count_if(schedule->dependencies,
                                             [kind = kind](const auto &edge) {
                                               return edge.kind == kind;
                                             })
                           << '\n';
          };
          auto regions = talos::analysis::getActivationRegionSchedule(views);
          print("region", regions);
          auto slices = talos::analysis::getActivationSliceSchedule(views);
          print("slice", slices);
          if (cycleRegions)
            slices = std::move(regions);
          if (slices && !sliceCycleFunction.empty()) {
            SmallVector<SmallVector<unsigned>> next(slices->nodes.size());
            for (auto edge : slices->dependencies)
              next[edge.source].push_back(edge.target);
            for (auto [root, step] : llvm::enumerate(slices->nodes)) {
              if (!slices->cyclic[slices->componentOf[root]] ||
                  step.activation->getActivationFunction().getSymName() !=
                      sliceCycleFunction)
                continue;
              SmallVector<unsigned> parent(slices->nodes.size(), UINT_MAX);
              SmallVector<unsigned> pending{unsigned(root)};
              parent[root] = root;
              unsigned last = UINT_MAX;
              for (unsigned cursor = 0;
                   cursor < pending.size() && last == UINT_MAX; ++cursor) {
                unsigned from = pending[cursor];
                for (unsigned target : next[from]) {
                  if (target == root) {
                    last = from;
                    break;
                  }
                  if (parent[target] == UINT_MAX) {
                    parent[target] = from;
                    pending.push_back(target);
                  }
                }
              }
              if (last == UINT_MAX)
                continue;
              SmallVector<unsigned> path;
              for (unsigned node = last; node != root; node = parent[node])
                path.push_back(node);
              path.push_back(root);
              llvm::errs() << (cycleRegions ? "region" : "slice")
                           << " cycle through @" << sliceCycleFunction << ':'
                           << root << '\n';
              for (unsigned node : llvm::reverse(path)) {
                const auto &piece = slices->nodes[node];
                llvm::errs()
                    << "  @"
                    << piece.activation->getActivationFunction().getSymName()
                    << ':' << node << " writes";
                talos::analysis::Ranges ranges;
                if (cycleRegions)
                  ranges = piece.activation->getNode(piece.operation)->writes;
                else if (!slices->slices[node].windows.empty())
                  for (const auto &[operation, range] :
                       slices->slices[node].windows)
                    ranges.push_back(range);
                else
                  for (Operation *store : slices->slices[node].stores)
                    llvm::append_range(
                        ranges,
                        piece.activation->getMemory().getWrites().lookup(
                            store));
                talos::analysis::normalize(ranges);
                for (auto range : ranges)
                  llvm::errs() << " s" << range.root << '[' << range.low << ','
                               << range.low + range.width << ')';
                llvm::errs() << '\n';
              }
            }
          }
        }
        if (sliceOrder) {
          auto order = talos::analysis::getActivationSliceOrder(views, &cycle);
          llvm::errs() << "slice graph: "
                       << (order           ? "acyclic"
                           : cycle.empty() ? "unavailable"
                                           : "cyclic")
                       << '\n';
        }
        if (publications) {
          auto order =
              talos::analysis::getActivationPublicationOrder(views, &cycle);
          llvm::errs() << "publication graph: "
                       << (order           ? "acyclic"
                           : cycle.empty() ? "unavailable"
                                           : "cyclic")
                       << '\n';
        }
        if (regionOrder) {
          auto order = talos::analysis::getActivationRegionOrder(views, &cycle);
          llvm::errs() << "region order: "
                       << (order           ? "acyclic"
                           : cycle.empty() ? "unavailable"
                                           : "cyclic")
                       << '\n';
          if (order)
            for (const auto &step : *order)
              step.activation->getNode(step.operation)
                  ->walk([&](Operation *op) {
                    auto store = dyn_cast<talos::sim::SimRefStoreOp>(op);
                    if (!store)
                      return;
                    auto found =
                        step.activation->getMemory().getWrites().find(store);
                    if (found != step.activation->getMemory().getWrites().end())
                      for (auto range : found->second)
                        llvm::errs()
                            << "  write s" << range.root << '[' << range.low
                            << ',' << range.low + range.width << ")\n";
                  });
        }
      }
    });
    markAllAnalysesPreserved();
  }

private:
  std::string snapshot(Operation *operation) {
    std::string text;
    if (verifyPreparedViews && operation) {
      llvm::raw_string_ostream os(text);
      operation->print(os);
    }
    return text;
  }
  void verifySnapshot(Operation *operation, const std::string &before) {
    if (snapshot(operation) != before) {
      getOperation().emitError("analysis rewrote a prepared activation view");
      signalPassFailure();
    }
  }
  /// Whenever full publication analysis has value dependencies, the cheaper
  /// input-only proof must succeed with the same publication inputs.
  void compare(talos::sim::SimFuncOp function,
               const talos::analysis::HandleDataflowAnalysis &handles) {
    using talos::analysis::ActivationMemoryAnalysis;
    using talos::analysis::ActivationRegionAnalysis;
    ActivationRegionAnalysis full(
        talos::analysis::prepareActivation(function), handles,
        ActivationMemoryAnalysis::DependencyMode::ReachingValues);
    if (!full.getMemory().hasValueDependencies())
      return;
    ActivationRegionAnalysis inputs(
        talos::analysis::prepareActivation(function), handles,
        ActivationMemoryAnalysis::DependencyMode::Inputs);
    if (!inputs.getMemory().hasInputDependencies() ||
        full.getMemory().getValueInputs() !=
            inputs.getMemory().getValueInputs()) {
      function.emitError("input-only dependency proof disagrees with full "
                         "publication analysis");
      return signalPassFailure();
    }
    llvm::errs() << "inputs @" << function.getSymName() << " agree\n";
  }
};
} // namespace
void talos::registerActivationMemoryAnalysisTestPass() {
  PassRegistration<RepeatableActivationTestPass>();
  PassRegistration<SourceMemoryForwardingTestPass>();
  PassRegistration<ActivationControlFlowTestPass>();
  PassRegistration<ActivationCanonicalizeTestPass>();
  PassRegistration<RegionValueDependencyTestPass>();
  PassRegistration<ActivationMemoryTestPass>();
  PassRegistration<ActivationRegionTestPass>();
}
