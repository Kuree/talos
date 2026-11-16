#include "talos/Analysis/NBAInfluenceAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/SymbolTable.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

using namespace mlir;
namespace talos::analysis {
namespace {
class InfluenceState final : public AnalysisState {
public:
  using AnalysisState::AnalysisState;
  bool observed = false;
  ChangeResult join(bool incoming) {
    if (!incoming || observed)
      return ChangeResult::NoChange;
    observed = true;
    return ChangeResult::Change;
  }
  void print(raw_ostream &os) const override { os << observed; }
};
using Dependencies = DenseMap<Operation *, SmallVector<Operation *>>;

// One sparse lattice per declared root, rather than a dense root bitvector at
// every instruction. Solver dependencies revisit predecessors when an observer
// reaches their successors. A root is never certified before convergence.
class InfluenceDataflow final : public DataFlowAnalysis {
public:
  InfluenceDataflow(DataFlowSolver &solver, const Dependencies &dependencies,
                    const DenseSet<Operation *> &seeds)
      : DataFlowAnalysis(solver), dependencies(dependencies), seeds(seeds) {}
  LogicalResult initialize(Operation *) override {
    for (const auto &entry : dependencies)
      if (failed(visit(getProgramPointBefore(entry.first))))
        return failure();
    return success();
  }
  LogicalResult visit(ProgramPoint *point) override {
    Operation *root = point->getNextOp();
    bool observed = seeds.contains(root);
    for (Operation *target : dependencies.at(root))
      observed |=
          getOrCreateFor<InfluenceState>(point, getProgramPointBefore(target))
              ->observed;
    auto *state = getOrCreate<InfluenceState>(point);
    propagateIfChanged(state, state->join(observed));
    return success();
  }

private:
  const Dependencies &dependencies;
  const DenseSet<Operation *> &seeds;
};
} // namespace

NBAInfluenceAnalysis::NBAInfluenceAnalysis(sim::SimDesignOp design,
                                           ArrayRef<Root> observers,
                                           bool guardedVPI) {
  if (!design || !design.getComputeGraphAttr() ||
      (!guardedVPI &&
       design.getComputeGraphAttr().getVpi() != schedule::ComputeVPIMode::Off))
    return;
  using Resource = schedule::ComputeResourceKind;
  using Effect = schedule::ComputeEffectKind;
  DenseMap<Root, Operation *> declarations;
  design.walk([&](sim::SimStorageDeclOp op) {
    declarations[{Resource::Storage, op.getId()}] = op;
  });
  design.walk([&](sim::SimNetDeclOp op) {
    declarations[{Resource::Net, op.getId()}] = op;
  });
  Dependencies dependencies;
  DenseSet<Operation *> seeds;
  for (const auto &entry : declarations) {
    dependencies[entry.second];
    known.insert(entry.first);
  }
  // Waveform dumping reads settled canonical state without a per-root Watch
  // effect. It permits batching but forbids erasing the stored value. Dynamic
  // scopes/depths conservatively make every root a possible reader target.
  bool dumpsState =
      design
          .walk([](Operation *op) {
            return isa<sim::SimDumpVarsOp, sim::SimDumpAllOp,
                       sim::SimDumpControlOp, sim::SimDumpFlushOp,
                       sim::SimDumpPortsOp, sim::SimDumpPortsControlOp>(op)
                       ? WalkResult::interrupt()
                       : WalkResult::advance();
          })
          .wasInterrupted();
  if (dumpsState)
    readers = known;
  for (Root root : observers) {
    auto found = declarations.find(root);
    if (found == declarations.end())
      return;
    seeds.insert(found->second);
  }
  bool resolved = true;
  design.walk([&](sim::SimNetConnectDeclOp connection) {
    Operation *lhs =
        declarations.lookup({Resource::Net, connection.getLhsNetId()});
    Operation *rhs =
        declarations.lookup({Resource::Net, connection.getRhsNetId()});
    if (!lhs || !rhs) {
      resolved = false;
      return;
    }
    // Root-wide may-alias closure; even a directed/partial connection is
    // conservatively bidirectional until a range-sensitive proof is available.
    dependencies[lhs].push_back(rhs);
    dependencies[rhs].push_back(lhs);
  });
  HandleDataflowAnalysis provenance(design);
  FormalEffectResolver formals(design, provenance);
  SymbolTable symbols(design);
  design.walk([&](sim::SimFuncOp function) {
    // Task-call scheduling edges do not instantiate the task's effects in
    // its caller summary. In particular, the implicit output copy-out reads
    // a static formal after its NBA has been captured. That formal persists
    // between calls (IEEE 1800-2023 13.3.2, 13.5), so its NBA is not unread.
    // Keep this reader inventory separate from immediate influence edges;
    // a write-only output actual does not make every root a possible reader.
    // Include immediate task dependencies too: a task can copy a read root
    // into another root observed by a conditional waiter (13.5, 9.4.2.3).
    // Called function effects are already instantiated in each caller summary.
    // Declaration initialization precedes process execution (LRM 6.8).
    if (function.getEntryKind() == sim::EntryKind::Function ||
        function.getEntryKind() == sim::EntryKind::RootInitializer)
      return;
    SmallVector<Operation *> inputs, outputs;
    auto record = [&](schedule::ComputeEffectAttr effect, bool input) {
      auto found =
          declarations.find({effect.getResource(), effect.getDescriptor()});
      if (found == declarations.end()) {
        resolved = false;
        return;
      }
      (input ? inputs : outputs).push_back(found->second);
      if (input)
        readers.insert({effect.getResource(), effect.getDescriptor()});
    };
    // A scalar copy-in and a private copy-out can connect effects on opposite
    // sides of a task call. Close the complete call inventory before forming
    // dependencies, rather than dropping those transfers at function bounds.
    SmallVector<sim::SimFuncOp> pending{function};
    DenseSet<Operation *> visited;
    while (!pending.empty()) {
      sim::SimFuncOp current = pending.pop_back_val();
      if (!visited.insert(current.getOperation()).second)
        continue;
      ArrayAttr summary = current.getEffectSummaryAttr();
      if (!summary) {
        resolved = false;
        continue;
      }
      current.walk([&](Operation *operation) {
        FlatSymbolRefAttr callee;
        // Function effects are already instantiated at each call site in the
        // caller's summary. Resolving a function's formals again would union
        // the actuals of every call site in the design into this process.
        if (auto call = dyn_cast<sim::SimTaskCallOp>(operation))
          callee = call.getCalleeAttr();
        else if (auto spawn = dyn_cast<sim::SimSpawnOp>(operation))
          callee = spawn.getCalleeAttr();
        if (!callee)
          return;
        if (auto target = symbols.lookup<sim::SimFuncOp>(callee.getValue()))
          pending.push_back(target);
        else
          resolved = false;
      });
      for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
        if (effect.getResource() == Resource::Unknown) {
          resolved = false;
          continue;
        }
        if (effect.getResource() != Resource::Storage &&
            effect.getResource() != Resource::Net)
          continue;
        bool input = effect.getEffect() == Effect::Read ||
                     effect.getEffect() == Effect::Watch;
        bool output = effect.getEffect() == Effect::Write ||
                      effect.getEffect() == Effect::Drive;
        // RHS/target evaluation remains at enqueue; no immediate dependency
        // crosses an NBA commit boundary (LRM 4.9.4).
        if (!input && !output)
          continue;
        if (effect.getTarget() == schedule::ComputeTargetKind::Formal) {
          // A write through a formal bound to a caller-private local cannot
          // alias a design root; the owner's closure carries that value on.
          // Private reads stay conservative.
          resolved &= formals.resolve(
              current.getSymNameAttr(), effect,
              [&](uint64_t, schedule::ComputeEffectAttr actual) {
                record(actual, input);
              },
              /*ignorePrivate=*/!input);
          continue;
        }
        if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor) {
          resolved = false;
          continue;
        }
        record(effect, input);
      }
    }
    for (Operation *input : inputs) {
      llvm::append_range(dependencies[input], outputs);
    }
  });
  if (!resolved)
    return;
  DataFlowSolver solver;
  solver.load<InfluenceDataflow>(dependencies, seeds);
  if (failed(solver.initializeAndRun(design)))
    return;
  for (const auto &entry : declarations) {
    const auto *state = solver.lookupState<InfluenceState>(
        solver.getProgramPointBefore(entry.second));
    if (!state)
      return;
    if (state->observed)
      observed.insert(entry.first);
  }
  complete = true;
}
} // namespace talos::analysis
