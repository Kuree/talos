#include "AnalysisTestPasses.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "talos/Analysis/ActivationPhaseAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/StringExtras.h"

using namespace mlir;
namespace {
using Analysis = talos::analysis::ActivationPhaseAnalysis;

/// Print a phase set as `-`, `any`, or a comma list where `32+` covers phase
/// 32 and every later phase.
void printSet(raw_ostream &os, Analysis::PhaseSet phases) {
  if (phases == Analysis::anyPhase) {
    os << "any";
    return;
  }
  if (!phases) {
    os << '-';
    return;
  }
  llvm::ListSeparator separator(",");
  for (unsigned bit = 0; bit != 32; ++bit)
    if (phases & (Analysis::PhaseSet{1} << bit))
      os << separator << bit + 1 << (bit == 31 ? "+" : "");
}
/// `{time-zero phases|later-slot phases}`.
void printPhases(raw_ostream &os, Analysis::Phases phases) {
  os << '{';
  printSet(os, phases.zero);
  os << '|';
  printSet(os, phases.later);
  os << '}';
}

class ActivationPhaseAnalysisTestPass
    : public PassWrapper<ActivationPhaseAnalysisTestPass,
                         OperationPass<ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ActivationPhaseAnalysisTestPass)
  ActivationPhaseAnalysisTestPass() = default;
  ActivationPhaseAnalysisTestPass(const ActivationPhaseAnalysisTestPass &other)
      : PassWrapper(other) {}
  StringRef getArgument() const final { return "test-talos-activation-phases"; }
  StringRef getDescription() const final {
    return "print time-slot phases of activations and root changes";
  }
  Option<bool> effectRoots{*this, "effect-roots", llvm::cl::init(false)};
  void runOnOperation() final {
    namespace sim = talos::sim;
    getOperation().walk([&](sim::SimDesignOp design) {
      talos::analysis::HandleDataflowAnalysis handles(design);
      Analysis analysis(design, handles);
      llvm::errs() << "phases " << design.getSymName()
                   << " valid=" << analysis.isValid() << '\n';
      for (auto function : design.getBody().front().getOps<sim::SimFuncOp>()) {
        if (function.isExternal() ||
            function.getEntryKind() == sim::EntryKind::RootInitializer ||
            (!effectRoots &&
             function.getEntryKind() == sim::EntryKind::Function))
          continue;
        llvm::errs() << "  @" << function.getSymName() << ':';
        unsigned index = 0;
        for (Block &block : function.getBody()) {
          llvm::errs() << " ^" << index++;
          printPhases(llvm::errs(), analysis.getPhases(&block));
          if (effectRoots)
            if (auto effects = analysis.getFragmentEffects(&block))
              for (auto effect :
                   effects.getAsRange<talos::schedule::ComputeEffectAttr>()) {
                auto kind = effect.getEffect();
                if (kind != talos::schedule::ComputeEffectKind::Write &&
                    kind != talos::schedule::ComputeEffectKind::Drive &&
                    kind != talos::schedule::ComputeEffectKind::NBA)
                  continue;
                llvm::errs() << " writes=";
                auto roots =
                    analysis.getEffectRoots(function.getSymNameAttr(), effect);
                if (!roots)
                  llvm::errs() << "unknown";
                else if (roots->empty())
                  llvm::errs() << "local";
                else
                  for (uint64_t root : *roots)
                    llvm::errs() << 's' << root << ',';
              }
        }
        llvm::errs() << '\n';
      }
      for (auto storage :
           design.getBody().front().getOps<sim::SimStorageDeclOp>()) {
        llvm::errs() << "  s" << storage.getId() << " changes ";
        printPhases(llvm::errs(), analysis.getChangePhases(storage.getId()));
        llvm::errs() << '\n';
      }
    });
    markAllAnalysesPreserved();
  }
};
} // namespace

void talos::registerActivationPhaseAnalysisTestPass() {
  PassRegistration<ActivationPhaseAnalysisTestPass>();
}
