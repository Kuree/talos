//===- FormalEffectAnalysis.cpp - Resolve direct formal bindings --------===//
#include "mlir/IR/SymbolTable.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Dialect/DPI/DPIDialect.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

using namespace mlir;
namespace talos::analysis {
FormalEffectResolver::FormalEffectResolver(
    sim::SimDesignOp design, const HandleDataflowAnalysis &provenanceAnalysis)
    : design(design.getOperation()), provenanceAnalysis(provenanceAnalysis) {}

bool FormalEffectResolver::resolve(
    StringAttr owner, schedule::ComputeEffectAttr effect,
    llvm::function_ref<void(uint64_t, schedule::ComputeEffectAttr)> emit,
    bool ignorePrivate) {
  if (!indexed)
    index();
  if (unsupportedCalls)
    return false;
  bool complete = true;
  using Formal = std::pair<StringAttr, unsigned>;
  SmallVector<Formal> pending{
      {owner, static_cast<unsigned>(effect.getFormal())}};
  DenseSet<Formal> seen;
  while (!pending.empty()) {
    auto [name, index] = pending.pop_back_val();
    if (!seen.insert({name, index}).second)
      continue;
    auto function =
        dyn_cast_or_null<sim::SimFuncOp>(functions.lookup(name.getValue()));
    auto sites = callers.find(name.getValue());
    if (!function || dpi::has<dpi::Export>(function) ||
        sites == callers.end()) {
      complete = false;
      continue;
    }
    for (Operation *site : sites->second) {
      ValueRange arguments = site->getOperands();
      if (auto task = dyn_cast<sim::SimTaskCallOp>(site))
        arguments = task.getArguments();
      auto caller = site->getParentOfType<sim::SimFuncOp>();
      if (!caller || index >= arguments.size()) {
        complete = false;
        continue;
      }
      auto [facts, inserted] = provenance.try_emplace(caller.getOperation());
      if (inserted)
        facts->second = provenanceAnalysis.derive(caller);
      auto actual = facts->second.find(arguments[index]);
      if (actual == facts->second.end()) {
        complete = false;
        continue;
      }
      const auto &target = actual->second;
      if (target.resource == schedule::ComputeResourceKind::Local) {
        complete &= ignorePrivate;
        continue;
      }
      if (target.resource != schedule::ComputeResourceKind::Storage &&
          target.resource != schedule::ComputeResourceKind::Net) {
        complete = false;
      } else if (target.descriptor) {
        // Resolve physical roots, not combinations of call paths. Widen
        // formal subranges within each root until an offset-sensitive call
        // proof is available; unrelated roots stay independent.
        emit(*target.descriptor,
             schedule::ComputeEffectAttr::get(
                 design->getContext(), effect.getEffect(), target.resource,
                 schedule::ComputeTargetKind::Descriptor, *target.descriptor, 0,
                 0, target.rootWidth, true, effect.getDeferred(),
                 effect.getTrigger()));
      } else if (target.formal) {
        pending.push_back({caller.getSymNameAttr(), *target.formal});
      } else {
        complete = false;
      }
    }
  }
  return complete;
}

void FormalEffectResolver::index() {
  indexed = true;
  for (sim::SimFuncOp function : cast<sim::SimDesignOp>(design)
                                     .getBody()
                                     .front()
                                     .getOps<sim::SimFuncOp>())
    functions[function.getSymName()] = function.getOperation();
  design->walk([&](Operation *op) {
    if (auto call = dyn_cast<sim::SimTaskCallOp>(op))
      callers[call.getCallee()].push_back(op);
    else if (auto call = dyn_cast<sim::SimCallOp>(op))
      callers[call.getCallee()].push_back(op);
    else if (auto spawn = dyn_cast<sim::SimSpawnOp>(op))
      callers[spawn.getCallee()].push_back(op);
    // Descriptor-dispatched call targets need their own complete binding
    // inventory. A direct-call inventory cannot certify those mutations.
    else if (isa<sim::SimClassVirtualTaskCallOp, sim::SimClassVirtualCallOp,
                 sim::SimClassDirectCallOp>(op))
      unsupportedCalls = true;
  });
}
} // namespace talos::analysis
