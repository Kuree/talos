//===- ActivationControlFlow.cpp - Edge-specific dispatch proofs
//-----------===//
#include "talos/Analysis/ActivationControlFlow.h"
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/DenseAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/RegionGraphTraits.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "talos/Analysis/GraphAlgorithms.h"
#include "talos/Analysis/OrderedDenseAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/SCCIterator.h"

using namespace mlir;
namespace talos::analysis {

LogicalResult canonicalizeActivationControlFlow(Operation *operation) {
  RewritePatternSet patterns(operation->getContext());
  operation->getContext()
      ->getLoadedDialect<sim::TalosSimulationDialect>()
      ->getCanonicalizationPatterns(patterns);
  for (RegisteredOperationName name :
       operation->getContext()->getRegisteredOperations())
    if (name.getDialectNamespace() == "arith" ||
        name.getDialectNamespace() == "cf")
      name.getCanonicalizationPatterns(patterns, operation->getContext());
  return applyPatternsGreedily(operation, std::move(patterns));
}

ControlActivationAnalysis::ControlActivationAnalysis(sim::SimDesignOp design) {
  DenseSet<uint64_t> targets;
  design.walk([&](Operation *op) {
    if (auto disable = dyn_cast<sim::SimControlDisableOp>(op))
      targets.insert(disable.getTargetId());
    else if (auto exit = dyn_cast<sim::SimControlNonlocalExitOp>(op))
      targets.insert(exit.getTargetId());
  });
  // Reports enqueued by a zero-time callee still belong to this process's
  // innermost active block. Propagate that effect through the reverse call
  // graph; unresolved/foreign calls can reenter SV and remain conservative.
  SymbolTable symbols(design);
  DenseMap<Operation *, SmallVector<Operation *>> callers;
  DenseSet<Operation *> reports;
  SmallVector<Operation *> pending;
  auto mayReport = [&](Operation *function) {
    if (reports.insert(function).second)
      pending.push_back(function);
  };
  for (auto function : design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (function.isExternal())
      mayReport(function);
    function.walk([&](Operation *op) {
      if (auto call = dyn_cast<sim::SimCallOp>(op)) {
        if (auto callee = symbols.lookup<sim::SimFuncOp>(call.getCallee()))
          callers[callee].push_back(function);
        else
          mayReport(function);
      } else if (isa<sim::SimDeferredEnqueueOp, sim::SimDPICallOp,
                     sim::SimTaskCallOp, sim::SimClassDirectCallOp,
                     sim::SimClassVirtualCallOp, sim::SimClassVirtualTaskCallOp,
                     sim::SimVPICallPrepareOp, CallOpInterface>(op))
        mayReport(function);
    });
  }
  for (unsigned index = 0; index < pending.size(); ++index)
    for (Operation *caller : callers[pending[index]])
      mayReport(caller);
  for (auto function : design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (reports.contains(function))
      continue;
    function.walk([&](sim::SimControlEnterOp enter) {
      if (!targets.contains(enter.getTargetId()) &&
          llvm::all_of(enter.getControl().getUsers(), [](Operation *user) {
            return isa<sim::SimControlLeaveOp>(user);
          }))
        enters[function].push_back(enter);
    });
  }
}

ArrayRef<Operation *> ControlActivationAnalysis::getUnobservableEnters(
    sim::SimFuncOp function) const {
  auto found = enters.find(function);
  return found == enters.end() ? ArrayRef<Operation *>{}
                               : ArrayRef<Operation *>(found->second);
}

namespace {
using Predicates = DenseMap<Value, bool>;
void forgetDefinitions(Predicates &facts, ValueRange definitions) {
  SmallVector<Value> remove;
  for (const auto &[predicate, truth] : facts) {
    auto compare = predicate.getDefiningOp<arith::CmpIOp>();
    if (llvm::is_contained(definitions, predicate) ||
        (compare && llvm::any_of(compare->getOperands(), [&](Value operand) {
           return llvm::is_contained(definitions, operand);
         })))
      remove.push_back(predicate);
  }
  for (Value value : remove)
    facts.erase(value);
}
class PredicateLattice final : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;
  bool reachable = false;
  Predicates predicates;
  ChangeResult merge(const Predicates &incoming) {
    if (!reachable) {
      reachable = true;
      predicates = incoming;
      return ChangeResult::Change;
    }
    size_t size = predicates.size();
    SmallVector<Value> remove;
    for (const auto &entry : predicates) {
      auto found = incoming.find(entry.first);
      if (found == incoming.end() || found->second != entry.second)
        remove.push_back(entry.first);
    }
    for (Value value : remove)
      predicates.erase(value);
    return predicates.size() == size ? ChangeResult::NoChange
                                     : ChangeResult::Change;
  }
  ChangeResult join(const AbstractDenseLattice &rhs) override {
    const auto &other = static_cast<const PredicateLattice &>(rhs);
    return other.reachable ? merge(other.predicates) : ChangeResult::NoChange;
  }
  void print(raw_ostream &os) const override { os << predicates.size(); }
};
class PredicateDataflow final
    : public OrderedDenseForwardDataFlowAnalysis<PredicateLattice> {
public:
  using OrderedDenseForwardDataFlowAnalysis::
      OrderedDenseForwardDataFlowAnalysis;
  LogicalResult visitOperation(Operation *op, const PredicateLattice &before,
                               PredicateLattice *after) override {
    if (!before.reachable)
      return success();
    auto next = before.predicates;
    // A dynamic execution of a definition supersedes facts from a prior loop
    // iteration. In particular a previous condition cannot prove itself.
    forgetDefinitions(next, op->getResults());
    propagateIfChanged(after, after->merge(next));
    return success();
  }
  void visitBlockTransfer(Block *block, ProgramPoint *, Block *predecessor,
                          const PredicateLattice &before,
                          PredicateLattice *after) override {
    if (!before.reachable)
      return;
    auto next = before.predicates;
    if (auto branch = dyn_cast<cf::CondBranchOp>(predecessor->getTerminator());
        branch && branch.getTrueDest() != branch.getFalseDest()) {
      bool value = branch.getTrueDest() == block;
      auto known = next.find(branch.getCondition());
      if (known != next.end() && known->second != value)
        return; // This incoming path contradicts a must-predicate.
      next[branch.getCondition()] = value;
    }
    // The branch tests the old bindings; destination arguments are rebound
    // afterwards. Do not carry that comparison into a new induction value.
    forgetDefinitions(next, block->getArguments());
    propagateIfChanged(after, after->merge(next));
  }

private:
  void setToEntryState(PredicateLattice *state) override {
    propagateIfChanged(state, state->merge(Predicates{}));
  }
};

/// Demand-driven constant propagation over the SSA slice of one condition.
/// Block arguments are translated along exactly one incoming edge. Folders
/// supply operation semantics; no opcode-specific algebra is assumed.
class EdgeConstants {
public:
  EdgeConstants(Block *target, ValueRange arguments, const Predicates &facts)
      : target(target), arguments(arguments), facts(facts) {}
  Attribute get(Value value) {
    if (auto found = constants.find(value); found != constants.end())
      return found->second;
    constants[value] = {}; // Cyclic or unsupported definitions stay unknown.
    if (auto found = facts.find(value); found != facts.end())
      return constants[value] =
                 BoolAttr::get(value.getContext(), found->second);
    // Canonicalization may turn !cmp into the inverse integer predicate.
    // Compare identical SSA operands only; do not infer relations between
    // four-state comparisons or distinct memory snapshots. The dense transfer
    // invalidates these relations when an operand is rebound by a loop.
    if (auto compare = value.getDefiningOp<arith::CmpIOp>())
      for (const auto &[predicate, truth] : facts) {
        auto known = predicate.getDefiningOp<arith::CmpIOp>();
        if (!known || known.getLhs() != compare.getLhs() ||
            known.getRhs() != compare.getRhs())
          continue;
        if (known.getPredicate() == compare.getPredicate())
          return constants[value] = BoolAttr::get(value.getContext(), truth);
        if (arith::invertPredicate(known.getPredicate()) ==
            compare.getPredicate())
          return constants[value] = BoolAttr::get(value.getContext(), !truth);
      }
    if (auto argument = dyn_cast<BlockArgument>(value)) {
      if (argument.getOwner() == target)
        return constants[value] = get(arguments[argument.getArgNumber()]);
      return {};
    }
    Attribute constant;
    if (matchPattern(value, m_Constant(&constant)))
      return constants[value] = constant;
    auto result = dyn_cast<OpResult>(value);
    Operation *op = result.getOwner();
    if (op->getNumRegions() || !isMemoryEffectFree(op) || !isSpeculatable(op))
      return {};
    SmallVector<Attribute> operands;
    for (Value operand : op->getOperands())
      operands.push_back(get(operand));
    // A folder may perform an in-place fold. Keep the analyzed CFG immutable
    // until every edge query has completed.
    OwningOpRef<Operation *> copy(op->clone());
    SmallVector<OpFoldResult> folded;
    if (failed(copy->fold(operands, folded)) ||
        folded.size() != op->getNumResults())
      return {};
    OpFoldResult replacement = folded[result.getResultNumber()];
    if (auto attribute = dyn_cast<Attribute>(replacement))
      return constants[value] = attribute;
    Value alias = cast<Value>(replacement);
    if (alias.getDefiningOp() == *copy)
      return {};
    return constants[value] = get(alias);
  }

private:
  Block *target;
  ValueRange arguments;
  const Predicates &facts;
  DenseMap<Value, Attribute> constants;
};
struct ThreadedEdge {
  Operation *predecessor;
  unsigned index;
  Block *target;
  SmallVector<Value> arguments;
};
} // namespace

// CFG canonicalization shares identical case tails, passing the selected
// references as block arguments. Recover edge-specific tails in a disposable
// view before exposing their publications. Every dynamic path still executes
// exactly one copy; no operation moves across a branch or a memory access.
bool specializeStaticHandleTails(Region &region,
                                 llvm::function_ref<bool(Block *)> eligible) {
  SmallVector<Block *> tails;
  for (Block &block : region) {
    auto branch = dyn_cast<cf::BranchOp>(block.getTerminator());
    if ((!eligible || eligible(&block)) &&
        llvm::any_of(block.getArguments(),
                     [](BlockArgument argument) {
                       return isa<sim::RefType, sim::NetType, sim::DriverType>(
                           argument.getType());
                     }) &&
        !block.hasOneUse() && branch && branch.getDestOperands().empty() &&
        block.getOperations().size() <= 128 &&
        llvm::all_of(block.getArguments(),
                     [&](BlockArgument argument) {
                       return llvm::all_of(argument.getUsers(),
                                           [&](Operation *user) {
                                             return user->getBlock() == &block;
                                           });
                     }) &&
        llvm::all_of(block, [&](Operation &op) {
          return !op.getNumRegions() &&
                 llvm::all_of(op.getUsers(), [&](Operation *user) {
                   return user->getBlock() == &block;
                 });
        }))
      tails.push_back(&block);
  }
  if (tails.empty())
    return false;
  // A process's wait/resume edge begins a new activation; it must not make
  // every otherwise acyclic case tail look like an induction-loop block.
  SmallVector<Block *> vertices;
  DenseMap<Block *, SmallVector<Block *>> edges;
  for (Block &block : region) {
    vertices.push_back(&block);
    if (!sim::isSuspensionOp(block.getTerminator()))
      llvm::append_range(edges[&block], block.getSuccessors());
  }
  DenseSet<Block *> cyclic;
  for (const auto &component :
       computeStronglyConnectedComponents<Block *>(vertices, edges))
    if (component.size() > 1 ||
        llvm::is_contained(edges.lookup(component.front()), component.front()))
      cyclic.insert(component.begin(), component.end());
  bool changed = false;
  unsigned growth = 0;
  for (Block *block : tails) {
    if (cyclic.contains(block))
      continue;
    SmallVector<std::pair<Operation *, unsigned>> edges;
    for (auto it = block->pred_begin(); it != block->pred_end(); ++it)
      edges.emplace_back((*it)->getTerminator(), it.getSuccessorIndex());
    if (edges.size() < 2 || edges.size() > 8 ||
        growth + edges.size() * block->getOperations().size() > 4096 ||
        llvm::any_of(edges, [](auto edge) {
          return !isa<cf::BranchOp, cf::CondBranchOp>(edge.first);
        }))
      continue;
    growth += edges.size() * block->getOperations().size();
    for (auto [term, index] : edges) {
      auto operands = cast<BranchOpInterface>(term).getSuccessorOperands(index);
      IRMapping mapping;
      mapping.map(block->getArguments(), operands.getForwardedOperands());
      auto *copy = new Block;
      region.getBlocks().insert(block->getIterator(), copy);
      OpBuilder builder = OpBuilder::atBlockEnd(copy);
      for (Operation &op : *block)
        builder.clone(op, mapping);
      operands.erase(0, operands.size());
      term->setSuccessor(copy, index);
    }
    block->erase();
    changed = true;
  }
  return changed;
}

bool threadActivationControlFlow(Region &region) {
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
  solver.load<dataflow::DeadCodeAnalysis>();
  solver.load<dataflow::SparseConstantPropagation>();
  solver.load<PredicateDataflow>();
  if (failed(solver.initializeAndRun(region.getParentOp())))
    return false;
  DominanceInfo dominance(region.getParentOp());
  SmallVector<ThreadedEdge> edges;
  for (Block &block : region) {
    auto dispatch = dyn_cast<cf::CondBranchOp>(block.getTerminator());
    if (!dispatch || block.hasNoPredecessors() || block.hasOneUse())
      continue;
    if (llvm::any_of(block.getPredecessors(), [&](Block *predecessor) {
          return dominance.dominates(&block, predecessor);
        }))
      continue; // Never peel even the initial iteration of a loop header.
    if (llvm::any_of(block.getArguments(), [&](BlockArgument argument) {
          return llvm::any_of(argument.getUsers(), [&](Operation *user) {
            return user->getBlock() != &block;
          });
        }))
      continue;
    // Bypass only control computations whose results do not escape. Every
    // selected successor operand must already exist at the incoming edge.
    if (llvm::any_of(block.without_terminator(), [&](Operation &op) {
          return op.getNumRegions() || !isMemoryEffectFree(&op) ||
                 !isSpeculatable(&op) ||
                 llvm::any_of(op.getUsers(), [&](Operation *user) {
                   return user->getBlock() != &block;
                 });
        }))
      continue;
    for (Block *predecessor : block.getPredecessors()) {
      Operation *term = predecessor->getTerminator();
      if (!isa<cf::BranchOp, cf::CondBranchOp>(term))
        continue;
      auto *state = solver.lookupState<PredicateLattice>(
          solver.getProgramPointBefore(term));
      if (!state || !state->reachable)
        continue;
      for (unsigned index = 0; index < term->getNumSuccessors(); ++index) {
        if (term->getSuccessor(index) != &block)
          continue;
        auto incoming = cast<BranchOpInterface>(term)
                            .getSuccessorOperands(index)
                            .getForwardedOperands();
        auto facts = state->predicates;
        if (auto branch = dyn_cast<cf::CondBranchOp>(term))
          facts[branch.getCondition()] = index == 0;
        forgetDefinitions(facts, block.getArguments());
        for (Operation &op : block.without_terminator())
          forgetDefinitions(facts, op.getResults());
        EdgeConstants constants(&block, incoming, facts);
        auto condition = dyn_cast_or_null<IntegerAttr>(
            constants.get(dispatch.getCondition()));
        if (!condition || !condition.getType().isInteger(1))
          continue;
        unsigned selected = condition.getValue().isZero() ? 1 : 0;
        Block *target = dispatch->getSuccessor(selected);
        if (target == &block)
          continue;
        ThreadedEdge edge{term, index, target, {}};
        bool available = true;
        for (Value value : cast<BranchOpInterface>(dispatch.getOperation())
                               .getSuccessorOperands(selected)
                               .getForwardedOperands()) {
          if (auto argument = dyn_cast<BlockArgument>(value);
              argument && argument.getOwner() == &block)
            value = incoming[argument.getArgNumber()];
          if (!dominance.dominates(value, term)) {
            available = false;
            break;
          }
          edge.arguments.push_back(value);
        }
        if (available)
          edges.push_back(std::move(edge));
      }
    }
  }
  for (const auto &edge : edges) {
    edge.predecessor->setSuccessor(edge.target, edge.index);
    if (auto branch = dyn_cast<cf::BranchOp>(edge.predecessor))
      branch.getDestOperandsMutable().assign(edge.arguments);
    else {
      auto conditional = cast<cf::CondBranchOp>(edge.predecessor);
      (edge.index == 0 ? conditional.getTrueDestOperandsMutable()
                       : conditional.getFalseDestOperandsMutable())
          .assign(edge.arguments);
    }
  }
  return !edges.empty();
}
} // namespace talos::analysis
