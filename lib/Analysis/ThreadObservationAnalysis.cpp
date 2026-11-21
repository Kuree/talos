#include "talos/Analysis/ThreadObservationAnalysis.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "talos/Dialect/Native/NativeRuntimeEntries.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

using namespace mlir;

namespace talos::analysis {

bool observesExecutingThread(Operation *operation) {
  if (isa<sim::SimProcessCurrentOp, sim::SimProcessStatusOp,
          sim::SimProcessControlOp, sim::SimProcessEventPendingOp,
          sim::SimProcessRandomStateOp, sim::SimProcessSetRandomStateOp,
          schedule::NativeProcessControlOp, sim::SimControlEnterOp,
          sim::SimControlBoundaryOp, sim::SimControlLeaveOp,
          sim::SimControlDisableOp, sim::SimControlDisableSelectedOp,
          sim::SimControlLocalBoundaryOp, sim::SimControlEscapePendingOp,
          schedule::NativeControlBoundaryOp, sim::SimSpawnOp,
          schedule::NativeSpawnOp, sim::SimCovergroupClockingSpawnOp>(
          operation))
    return true;
  if (auto dpi = dyn_cast<sim::SimDPICallOp>(operation))
    return dpi.getIsContext();
  // Native preparation lowers some of the operations above, and DPI imports,
  // to runtime calls before eval owners are planned.
  auto call = dyn_cast<LLVM::CallOp>(operation);
  std::optional<StringRef> callee = call ? call.getCallee() : std::nullopt;
  return callee &&
         hasNativeRuntimeEffect(*callee, native_runtime::ObservesThread);
}

namespace {

class ObservationState final : public AnalysisState {
public:
  using AnalysisState::AnalysisState;
  bool observes = false;
  ChangeResult join(bool incoming) {
    if (!incoming || observes)
      return ChangeResult::NoChange;
    observes = true;
    return ChangeResult::Change;
  }
  void print(raw_ostream &os) const override { os << observes; }
};

struct LocalObservation {
  bool observes = false;
  SmallVector<Operation *> callees;
};

bool isFunction(Operation *operation) {
  return isa<sim::SimFuncOp, LLVM::LLVMFuncOp>(operation);
}

/// The callee summary of one function body, then a monotone join over the call
/// graph: a function observes its thread if it, or anything it can call, does.
class ObservationDataflow final : public DataFlowAnalysis {
public:
  using DataFlowAnalysis::DataFlowAnalysis;
  LogicalResult initialize(Operation *root) override {
    SymbolTableCollection symbols;
    auto summarize = [&](Operation *function) {
      auto &summary = local[function];
      auto *body = &function->getRegion(0);
      if (body->empty()) {
        // An external LLVM declaration is a runtime service or foreign code:
        // only the services named by observesExecutingThread observe the
        // thread, and they are classified at their call sites.
        summary.observes = isa<sim::SimFuncOp>(function);
        return;
      }
      function->walk([&](Operation *operation) {
        if (summary.observes || operation == function)
          return;
        if (observesExecutingThread(operation)) {
          summary.observes = true;
          return;
        }
        auto call = dyn_cast<CallOpInterface>(operation);
        if (!call)
          return;
        auto symbol = dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
        Operation *callee =
            symbol ? symbols.lookupNearestSymbolFrom(operation, symbol)
                   : nullptr;
        if (callee && isFunction(callee) &&
            (callee == root || root->isProperAncestor(callee)))
          summary.callees.push_back(callee);
        else if (!callee || !isa<LLVM::LLVMFuncOp>(callee))
          // Indirect, virtual or unresolved targets may reach anything.
          summary.observes = true;
      });
    };
    root->walk([&](Operation *operation) {
      if (isFunction(operation))
        summarize(operation);
    });
    for (auto &entry : local)
      if (failed(visit(getProgramPointBefore(entry.first))))
        return failure();
    return success();
  }
  LogicalResult visit(ProgramPoint *point) override {
    Operation *function = point->getNextOp();
    auto found = local.find(function);
    if (found == local.end())
      return success();
    bool observes = found->second.observes;
    for (Operation *callee : found->second.callees)
      observes |= getOrCreateFor<ObservationState>(
                      point, getProgramPointBefore(callee))
                      ->observes;
    auto *state = getOrCreate<ObservationState>(point);
    propagateIfChanged(state, state->join(observes));
    return success();
  }

private:
  DenseMap<Operation *, LocalObservation> local;
};

} // namespace

ThreadObservationAnalysis::ThreadObservationAnalysis(Operation *root) {
  DataFlowSolver solver;
  solver.load<ObservationDataflow>();
  if (failed(solver.initializeAndRun(root)))
    return;
  root->walk([&](Operation *operation) {
    if (!isFunction(operation))
      return;
    if (auto *state = solver.lookupState<ObservationState>(
            solver.getProgramPointBefore(operation)))
      observing.try_emplace(operation, state->observes);
  });
}

bool ThreadObservationAnalysis::observes(Operation *function) const {
  auto found = observing.find(function);
  return found == observing.end() || found->second;
}

} // namespace talos::analysis
