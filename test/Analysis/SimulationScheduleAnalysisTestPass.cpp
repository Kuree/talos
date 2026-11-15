//===- SimulationScheduleAnalysisTestPass.cpp - Print schedule facts -----===//

#include "AnalysisTestPasses.h"

#include "talos/Analysis/SimulationScheduleAnalysis.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace {

class SimulationScheduleAnalysisTestPass
    : public PassWrapper<SimulationScheduleAnalysisTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(
      SimulationScheduleAnalysisTestPass)
  SimulationScheduleAnalysisTestPass() = default;
  SimulationScheduleAnalysisTestPass(
      const SimulationScheduleAnalysisTestPass &other)
      : PassWrapper(other) {}

  StringRef getArgument() const final {
    return "test-talos-simulation-schedule-analysis";
  }
  StringRef getDescription() const final {
    return "print shared native and bytecode schedule ranks";
  }
  Option<bool> preemptions{*this, "preemptions", llvm::cl::init(false)};

  void runOnOperation() final {
    SmallVector<talos::sim::SimDesignOp> designs(
        getOperation().getOps<talos::sim::SimDesignOp>());
    llvm::sort(designs, [](auto lhs, auto rhs) {
      return lhs.getSymName() < rhs.getSymName();
    });
    for (talos::sim::SimDesignOp design : designs) {
      FailureOr<talos::analysis::SimulationScheduleAnalysis> analysis =
          talos::analysis::SimulationScheduleAnalysis::compute(design);
      if (failed(analysis)) {
        signalPassFailure();
        return;
      }
      printDesign(design, *analysis);
      if (preemptions)
        design.walk([&](talos::sim::SimSuspendDelayOp delay) {
          auto after = talos::schedule::get<
              talos::schedule::Field::ActivePreemptionAfter>(delay);
          auto runs = talos::schedule::get<
              talos::schedule::Field::ActivePreemptionRuns>(delay);
          if (runs) {
            bool ordered = true;
            std::optional<uint32_t> previous;
            DenseSet<Operation *> seen;
            for (auto [index, raw] : llvm::enumerate(runs)) {
              auto actor = design.lookupSymbol<talos::sim::SimFuncOp>(
                  cast<FlatSymbolRefAttr>(raw).getValue());
              std::optional<uint32_t> rank;
              if (actor && seen.insert(actor).second) {
                rank = analysis->getEntryRank(actor);
                actor.walk([&](Operation *wait) {
                  if (isa<talos::sim::SimSuspendChangeOp,
                          talos::sim::SimSuspendAnyOp>(wait)) {
                    auto body = analysis->getBlockRank(wait->getSuccessor(0));
                    if (rank && body)
                      rank = std::max(*rank, *body);
                  }
                });
              } else if (actor) {
                actor.walk([&, index = index](
                               talos::sim::SimSuspendDelayOp handoff) {
                  auto path = talos::schedule::get<
                      talos::schedule::Field::ActivePreemptionRuns>(handoff);
                  auto resume = talos::schedule::get<
                      talos::schedule::Field::ActivePreemptionResume>(handoff);
                  if (path == runs && resume && resume.getUInt() == index) {
                    auto current =
                        analysis->getBlockRank(handoff.getContinuation());
                    if (rank)
                      ordered &= current && *current == *rank;
                    else
                      rank = current;
                  }
                });
              }
              ordered &= rank && (!previous || *rank > *previous);
              previous = rank;
            }
            llvm::errs()
                << "preemption @"
                << delay->getParentOfType<talos::sim::SimFuncOp>().getSymName()
                << " ordered=" << ordered << '\n';
            if (!ordered) {
              delay.emitError("preemption does not preserve the selected runs");
              signalPassFailure();
            }
            return;
          }
          if (!after)
            return;
          auto rank = analysis->getBlockRank(delay.getContinuation());
          bool ordered = rank.has_value();
          auto owner = delay->getParentOfType<talos::sim::SimFuncOp>();
          auto startRank = [&](talos::sim::SimFuncOp function) {
            auto result = analysis->getEntryRank(function);
            function.walk([&](Operation *wait) {
              if (isa<talos::sim::SimSuspendChangeOp,
                      talos::sim::SimSuspendAnyOp>(wait)) {
                auto body = analysis->getBlockRank(wait->getSuccessor(0));
                if (result && body)
                  result = std::max(*result, *body);
              }
            });
            return result;
          };
          auto previous = startRank(owner);
          for (Attribute raw : after) {
            auto name = cast<FlatSymbolRefAttr>(raw);
            auto peer =
                design.lookupSymbol<talos::sim::SimFuncOp>(name.getValue());
            auto entry = peer ? analysis->getEntryRank(peer) : std::nullopt;
            ordered &= entry && rank && *rank > *entry;
            if (peer) {
              auto start = startRank(peer);
              ordered &= previous && start && *start > *previous;
              previous = start;
              peer.walk([&](Operation *wait) {
                if (isa<talos::sim::SimSuspendChangeOp,
                        talos::sim::SimSuspendAnyOp>(wait)) {
                  auto resume = analysis->getBlockRank(wait->getSuccessor(0));
                  ordered &= resume && rank && *rank > *resume;
                }
              });
            }
          }
          llvm::errs()
              << "preemption @"
              << delay->getParentOfType<talos::sim::SimFuncOp>().getSymName()
              << " ordered=" << ordered << '\n';
          if (!ordered) {
            delay.emitError(
                "preemption does not preserve the selected run order");
            signalPassFailure();
          }
          for (auto producer : analysis->getPreemptionPrerequisites(owner)) {
            auto producerRank = analysis->getEntryRank(producer);
            bool inputOrdered = producerRank.has_value();
            producer.walk([&](Operation *wait) {
              if (isa<talos::sim::SimSuspendChangeOp,
                      talos::sim::SimSuspendAnyOp>(wait)) {
                auto resume = analysis->getBlockRank(wait->getSuccessor(0));
                if (resume && producerRank)
                  producerRank = std::max(*producerRank, *resume);
              }
            });
            auto entry = analysis->getEntryRank(owner);
            inputOrdered &= entry && producerRank && *entry > *producerRank;
            owner.walk([&](Operation *wait) {
              if (isa<talos::sim::SimSuspendChangeOp,
                      talos::sim::SimSuspendAnyOp>(wait)) {
                auto resume = analysis->getBlockRank(wait->getSuccessor(0));
                inputOrdered &=
                    resume && producerRank && *resume > *producerRank;
              }
            });
            llvm::errs() << "preemption input @" << owner.getSymName()
                         << " after @" << producer.getSymName()
                         << " ordered=" << inputOrdered << '\n';
            if (!inputOrdered) {
              delay.emitError("preemption precedes an independent input");
              signalPassFailure();
            }
          }
        });
    }
    markAllAnalysesPreserved();
  }

private:
  static void
  printDesign(talos::sim::SimDesignOp design,
              const talos::analysis::SimulationScheduleAnalysis &analysis) {
    llvm::errs() << "schedule @" << design.getSymName() << "\n";
    SmallVector<talos::sim::SimFuncOp> functions;
    design.walk([&](talos::sim::SimFuncOp function) {
      if (analysis.getEntryRank(function.getOperation()))
        functions.push_back(function);
    });
    llvm::sort(functions, [](auto lhs, auto rhs) {
      return lhs.getSymName() < rhs.getSymName();
    });
    for (talos::sim::SimFuncOp function : functions) {
      llvm::errs() << "  func @" << function.getSymName() << " entry="
                   << *analysis.getEntryRank(function.getOperation()) << "\n";
      for (auto [index, block] : llvm::enumerate(function.getBody()))
        if (std::optional<uint32_t> rank = analysis.getBlockRank(&block))
          llvm::errs() << "    bb" << index << " rank=" << *rank << "\n";
    }
  }
};

} // namespace

namespace talos {

void registerSimulationScheduleAnalysisTestPass() {
  PassRegistration<SimulationScheduleAnalysisTestPass>();
}

} // namespace talos
