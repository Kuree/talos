//===- MarkContributionMirrors.cpp - Drivers whose slot equals the net ----===//

#include "talos/Analysis/ContributionMirrorAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_TALOSSIMMARKCONTRIBUTIONMIRRORSPASS
#include "talos/Dialect/Simulation/Transforms/Passes.h.inc"

namespace {
class MarkContributionMirrorsPass final
    : public impl::TalosSimMarkContributionMirrorsPassBase<
          MarkContributionMirrorsPass> {
public:
  using Base::Base;

  void runOnOperation() override {
    sim::SimDesignOp design = getOperation();
    if (vpi != "off" && vpi != "read" && vpi != "full") {
      design.emitError("invalid VPI contribution mirror contract");
      return signalPassFailure();
    }
    if (design.getBody().empty())
      return markAllAnalysesPreserved();
    for (auto driver : design.getBody().front().getOps<sim::SimDriverDeclOp>())
      sim::remove<sim::metadata::ContributionMirrorsNet>(driver);
    // IEEE 1800-2023 38.34, 38.35, 10.6.2: a writable VPI client can force
    // any net, and its release must restore the drivers' values from their
    // slots.
    if (vpi == "full")
      return;
    DenseSet<uint64_t> mirrors =
        analysis::computeContributionMirrorDrivers(design);
    for (auto driver : design.getBody().front().getOps<sim::SimDriverDeclOp>())
      if (mirrors.contains(driver.getId())) {
        sim::mark<sim::metadata::ContributionMirrorsNet>(driver);
        ++numDrivers;
      }
  }
};
} // namespace
} // namespace talos
