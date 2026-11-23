//===- ActivationRegionAnalysis.cpp - CFG activation regions -------------===//
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "mlir/Analysis/CFGLoopInfo.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/RegionGraphTraits.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Analysis/ActivationControlFlow.h"
#include "talos/Analysis/BoundedLoopAnalysis.h"
#include "talos/Analysis/DemandedBitAnalysis.h"
#include "talos/Analysis/GraphAlgorithms.h"
#include "talos/Analysis/LocalStorageAnalysis.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Runtime/ActivationOrder.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SetVector.h"
#include <array>
#include <functional>
#include <map>
#include <numeric>
#include <queue>
#include <set>

using namespace mlir;
namespace talos::analysis {
namespace {
using Ranges = ActivationMemoryAnalysis::Ranges;

void unionRanges(Ranges &into, ArrayRef<ActivationMemoryAnalysis::Range> from) {
  llvm::append_range(into, from);
  llvm::sort(into, [](const auto &a, const auto &b) {
    return std::tie(a.root, a.low, a.width) < std::tie(b.root, b.low, b.width);
  });
  Ranges merged;
  for (auto range : into) {
    if (!merged.empty() && merged.back().root == range.root &&
        range.low <= merged.back().low + merged.back().width) {
      auto &last = merged.back();
      last.width =
          std::max(last.low + last.width, range.low + range.width) - last.low;
    } else
      merged.push_back(range);
  }
  into = std::move(merged);
}
/// The bits present in both range sets; both are sound over-approximations of
/// one dependence, so their intersection is one too.
Ranges intersectRanges(ArrayRef<ActivationMemoryAnalysis::Range> a,
                       ArrayRef<ActivationMemoryAnalysis::Range> b) {
  Ranges result;
  for (const auto &x : a)
    for (const auto &y : b) {
      if (x.root != y.root)
        continue;
      uint64_t low = std::max(x.low, y.low);
      uint64_t high = std::min(x.low + x.width, y.low + y.width);
      if (low < high)
        result.push_back({x.root, low, high - low});
    }
  Ranges normalized;
  unionRanges(normalized, result);
  return normalized;
}

} // namespace

StringRef
stringifyActivationFailure(ActivationRegionAnalysis::FailureReason reason) {
  using FailureReason = ActivationRegionAnalysis::FailureReason;
  switch (reason) {
  case FailureReason::None:
    return {};
  case FailureReason::ActivationShape:
    return "activation shape";
  case FailureReason::InitialResumeEquivalence:
    return "initial/resume equivalence";
  case FailureReason::Termination:
    return "termination";
  case FailureReason::MemoryEffects:
    return "memory effects";
  case FailureReason::UnmappedMemoryAccess:
    return "unmapped memory access";
  }
  llvm_unreachable("unknown activation failure");
}

ActivationRegionAnalysis::ActivationRegionAnalysis(
    PreparedActivation prepared, const HandleDataflowAnalysis &handles,
    ActivationMemoryAnalysis::DependencyMode mode)
    : view(std::move(prepared.view)), suspension(prepared.suspension),
      sourceFunction(prepared.source), symbols(prepared.getSymbolTable()),
      sourceActivation(prepared.sourceActivation), dependencyMode(mode),
      reason(prepared.reason) {
  if (!prepared.isValid())
    return;
  sim::SimFuncOp initial = view.get();
  // Preparation has finished every CFG rewrite. Facts and scheduling units
  // refer to this frozen revision for the entire analysis lifetime.
  memory =
      ActivationMemoryAnalysis(initial, handles, 65536, mode, symbols);
  if (!memory.isValid()) {
    reason = FailureReason::MemoryEffects;
    return;
  }
  reason = FailureReason::ActivationShape;
  const auto &reads = memory.getReads();
  const auto &writes = memory.getWrites();
  // The dense solver visits every feasible activation path. Frontend slice
  // lowering may retain out-of-bounds arms that no proven induction value
  // reaches. Record those exact source sites; a newly introduced or cloned
  // access must still have its own effect mapping.
  DenseSet<Operation *> unreachableAccesses;
  initial->walk([&](Operation *op) {
    if ((isa<sim::SimRefLoadOp, sim::SimNetReadOp>(op) &&
         !reads.contains(op)) ||
        (isa<sim::SimRefStoreOp, sim::SimDriverDriveOp>(op) &&
         !writes.contains(op)))
      unreachableAccesses.insert(op);
  });
  Region &body = initial.getBody();
  Block *exit = nullptr;
  for (Block &block : body)
    if (isa<sim::SimReturnOp>(block.getTerminator())) {
      if (exit)
        return;
      exit = &block;
    }
  if (!exit)
    return;
  // A block on a CFG cycle executes a variable number of times, so it never
  // bounds a top-level statement. Every remaining dominator of the exit runs
  // exactly once on every path through the activation.
  DenseSet<Block *> cyclic;
  for (auto scc = llvm::scc_begin(&body); !scc.isAtEnd(); ++scc)
    if (scc.hasCycle())
      cyclic.insert(scc->begin(), scc->end());
  SmallVector<Block *> chain;
  if (body.hasOneBlock()) {
    chain.push_back(exit);
  } else {
    DominanceInfo dominance(initial);
    for (auto *node = dominance.getNode(exit); node; node = node->getIDom())
      if (Block *block = node->getBlock(); block && !cyclic.contains(block))
        chain.push_back(block);
    std::reverse(chain.begin(), chain.end());
  }
  if (chain.empty() || chain.front() != &body.front())
    return;
  DenseSet<Block *> covered(chain.begin(), chain.end());
  auto addNode = [&](Node node) {
    unsigned id = nodes.size();
    nodes.push_back(std::move(node));
    nodes.back().walk([&](Operation *op) { nodeIndices[op] = id; });
    return id;
  };
  for (auto [index, block] : llvm::enumerate(chain)) {
    for (Operation &op : block->without_terminator())
      addNode({&op, {}, nullptr, {}, {}});
    if (block == exit)
      break;
    // Every block strictly between two chain blocks belongs to the region
    // entered by the first block's branch; the next chain block is its join.
    Block *join = chain[index + 1];
    Node region{block->getTerminator(), {}, join, {}, {}};
    SmallVector<Block *> pending(block->getSuccessors());
    DenseSet<Block *> inside;
    while (!pending.empty()) {
      Block *next = pending.pop_back_val();
      if (next == join || !inside.insert(next).second)
        continue;
      if (covered.contains(next))
        return;
      llvm::append_range(pending, next->getSuccessors());
    }
    for (Block &candidate : body)
      if (inside.contains(&candidate)) {
        region.blocks.push_back(&candidate);
        covered.insert(&candidate);
      }
    unsigned id = addNode(std::move(region));
    for (Block *inner : nodes[id].blocks)
      argumentNodes[inner] = id;
    argumentNodes[join] = id;
  }
  if (covered.size() != body.getBlocks().size()) {
    nodes.clear();
    nodeIndices.clear();
    argumentNodes.clear();
    return;
  }
  for (Node &node : nodes) {
    bool accounted = true;
    node.walk([&](Operation *nested) {
      if (isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimCallOp>(nested)) {
        auto found = reads.find(nested);
        if (found == reads.end())
          accounted &= isa<sim::SimCallOp>(nested) ||
                       unreachableAccesses.contains(nested);
        else
          unionRanges(node.reads, found->second);
      } else if (isa<sim::SimRefStoreOp, sim::SimDriverDriveOp>(nested)) {
        auto found = writes.find(nested);
        if (found == writes.end())
          accounted &= unreachableAccesses.contains(nested);
        else
          unionRanges(node.writes, found->second);
      }
    });
    if (!accounted) {
      nodes.clear();
      nodeIndices.clear();
      argumentNodes.clear();
      reason = FailureReason::UnmappedMemoryAccess;
      return;
    }
  }
  SmallVector<Value> watched;
  if (auto change = dyn_cast<sim::SimSuspendChangeOp>(suspension))
    watched.push_back(change.getWatched());
  else
    llvm::append_range(watched,
                       cast<sim::SimSuspendAnyOp>(suspension).getWatched());
  auto facts = handles.derive(sourceFunction);
  watchedRanges.emplace();
  for (Value watch : watched) {
    auto fact = facts.find(watch);
    auto span = sim::getProvenanceSpan(watch.getType());
    if (fact == facts.end() || !fact->second.descriptor ||
        fact->second.dynamic || !span || fact->second.width != *span) {
      watchedRanges.reset();
      break;
    }
    auto root = ActivationMemoryAnalysis::getRoot(fact->second.resource,
                                                  *fact->second.descriptor);
    if (!root) {
      watchedRanges.reset();
      break;
    }
    watchedRanges->push_back({*root, fact->second.low, fact->second.width});
  }
  if (watchedRanges)
    normalize(*watchedRanges);
  reason = FailureReason::None;
}

void ActivationRegionAnalysis::Node::walk(
    function_ref<void(Operation *)> callback) const {
  operation->walk(callback);
  for (Block *block : blocks)
    for (Operation &op : *block)
      op.walk(callback);
}

const ActivationRegionAnalysis::Node *
ActivationRegionAnalysis::getNode(Operation *operation) const {
  auto found = nodeIndices.find(operation);
  return found == nodeIndices.end() ? nullptr : &nodes[found->second];
}

const ActivationRegionAnalysis::Node *
ActivationRegionAnalysis::getDefiningNode(Value value) const {
  if (Operation *definition = value.getDefiningOp())
    return getNode(definition);
  auto found = argumentNodes.find(cast<BlockArgument>(value).getOwner());
  return found == argumentNodes.end() ? nullptr : &nodes[found->second];
}

namespace {
bool buildComponents(ActivationSchedule &schedule) {
  llvm::sort(schedule.dependencies, [](const auto &a, const auto &b) {
    return std::tie(a.source, a.target, a.kind) <
           std::tie(b.source, b.target, b.kind);
  });
  schedule.dependencies.erase(
      std::unique(schedule.dependencies.begin(), schedule.dependencies.end(),
                  [](const auto &a, const auto &b) {
                    return a.source == b.source && a.target == b.target &&
                           a.kind == b.kind;
                  }),
      schedule.dependencies.end());
  std::vector<std::pair<uint32_t, uint32_t>> edges;
  for (auto dependency : schedule.dependencies)
    edges.emplace_back(dependency.source, dependency.target);
  runtime::ActivationOrder order;
  if (!runtime::ActivationOrder::build(schedule.nodes.size(), std::move(edges),
                                       order))
    return false;
  llvm::append_range(schedule.order, order.nodes);
  llvm::append_range(schedule.componentOffsets, order.componentOffsets);
  llvm::append_range(schedule.componentOf, order.componentOf);
  for (bool cyclic : order.cyclic)
    schedule.cyclic.push_back(cyclic);
  return true;
}

std::optional<SmallVector<ActivationRegionStep>>
orderSteps(ArrayRef<ActivationRegionStep> steps,
           SmallVector<std::pair<unsigned, unsigned>> edges,
           SmallVectorImpl<ActivationRegionStep> *cycle) {
  if (cycle)
    cycle->clear();
  llvm::sort(edges);
  edges.erase(std::unique(edges.begin(), edges.end()), edges.end());
  SmallVector<SmallVector<unsigned>> successors(steps.size());
  SmallVector<unsigned> incoming(steps.size(), 0);
  for (auto [from, to] : edges) {
    successors[from].push_back(to);
    ++incoming[to];
  }
  std::priority_queue<unsigned, SmallVector<unsigned>, std::greater<unsigned>>
      ready;
  for (unsigned id = 0; id < steps.size(); ++id)
    if (!incoming[id])
      ready.push(id);
  SmallVector<ActivationRegionStep> result;
  while (!ready.empty()) {
    unsigned id = ready.top();
    ready.pop();
    result.push_back(steps[id]);
    for (unsigned next : successors[id])
      if (!--incoming[next])
        ready.push(next);
  }
  if (result.size() != steps.size()) {
    if (cycle) {
      // An iterative depth-first walk gives a deterministic directed witness,
      // including the source-order paths between cross-activation accesses.
      // Do this only when a caller requests cycle information.
      struct Frame {
        unsigned node;
        unsigned successor = 0;
      };
      SmallVector<uint8_t> color(steps.size(), 0);
      SmallVector<Frame> path;
      for (unsigned root = 0; root < steps.size() && cycle->empty(); ++root) {
        if (!incoming[root] || color[root])
          continue;
        color[root] = 1;
        path.push_back({root});
        while (!path.empty() && cycle->empty()) {
          auto &frame = path.back();
          if (frame.successor == successors[frame.node].size()) {
            color[frame.node] = 2;
            path.pop_back();
            continue;
          }
          unsigned next = successors[frame.node][frame.successor++];
          if (color[next] == 1) {
            auto start = llvm::find_if(
                path, [&](const Frame &entry) { return entry.node == next; });
            for (auto it = start; it != path.end(); ++it)
              cycle->push_back(steps[it->node]);
          } else if (!color[next]) {
            color[next] = 1;
            path.push_back({next});
          }
        }
      }
    }
    return std::nullopt;
  }
  return result;
}
} // namespace

namespace {
/// Loads an operation depends on through SSA values, CFG block arguments and
/// the branches that decide whether it executes. Block arguments depend on
/// every incoming operand and on the branches selecting the incoming edge.
class ActivationLoadSlice {
public:
  ActivationLoadSlice(sim::SimFuncOp function,
                      const ActivationMemoryAnalysis &memory)
      : ActivationLoadSlice(function, memory.getReads(), memory.getWrites(),
                            &memory.getPrivateReads()) {}
  ActivationLoadSlice(sim::SimFuncOp function,
                      const DenseMap<Operation *, Ranges> &reads,
                      const DenseMap<Operation *, Ranges> &writes,
                      const DenseSet<Operation *> *privateReads = nullptr)
      : reads(reads), privateReads(privateReads), locals(function) {
    // Accesses outside the design inventory are private slots (or dead
    // arms). A private load may observe any private store of the activation.
    function.walk([&](sim::SimRefStoreOp store) {
      if (!writes.contains(store))
        privateStores.push_back(store);
    });
    if (function.getBody().hasOneBlock())
      return;
    PostDominanceInfo postDominance(function);
    for (Block &block : function.getBody()) {
      Operation *term = block.getTerminator();
      if (!isa<cf::CondBranchOp, cf::SwitchOp>(term))
        continue;
      auto *node = postDominance.getNode(&block);
      auto *stop = node ? node->getIDom() : nullptr;
      for (Block *successor : block.getSuccessors())
        for (auto *runner = postDominance.getNode(successor);
             runner && runner != stop; runner = runner->getIDom())
          if (Block *controlled = runner->getBlock())
            controllers[controlled].insert(term);
    }
  }
  void collect(Operation *root, SmallVectorImpl<Operation *> &loads,
               DenseSet<Operation *> *required = nullptr) const {
    SmallVector<Operation *> pendingOps{root};
    SmallVector<Value> pendingValues;
    DenseSet<Operation *> seenOps{root};
    DenseSet<Value> seenValues;
    DenseSet<Block *> seenBlocks;
    auto visitBlock = [&](Block *block) {
      if (!seenBlocks.insert(block).second)
        return;
      for (Operation *term : controllers.lookup(block))
        if (seenOps.insert(term).second)
          pendingOps.push_back(term);
    };
    while (!pendingOps.empty() || !pendingValues.empty()) {
      if (!pendingOps.empty()) {
        Operation *op = pendingOps.pop_back_val();
        if (isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimCallOp>(op) &&
            reads.contains(op))
          loads.push_back(op);
        if (auto load = dyn_cast<sim::SimRefLoadOp>(op);
            load && (!reads.contains(op) ||
                     (privateReads && privateReads->contains(op)))) {
          auto root = locals.lookup(load.getReference());
          for (Operation *store : privateStores)
            if ((!root ||
                 locals.lookup(
                     cast<sim::SimRefStoreOp>(store).getReference()) == root) &&
                seenOps.insert(store).second)
              pendingOps.push_back(store);
        }
        if (isa<sim::SimCallOp>(op) &&
            llvm::any_of(op->getOperandTypes(),
                         [](Type type) { return isa<sim::RefType>(type); }))
          for (Operation *store : privateStores)
            if (seenOps.insert(store).second)
              pendingOps.push_back(store);
        visitBlock(op->getBlock());
        op->walk([&](Operation *nested) {
          // Successor operands are separate SSA lanes. Visiting a branch as
          // a control dependency must not import every other forwarded lane.
          auto visit = [&](Value operand) {
            if (seenValues.insert(operand).second)
              pendingValues.push_back(operand);
          };
          if (auto branch = dyn_cast<cf::CondBranchOp>(nested))
            visit(branch.getCondition());
          else if (auto branch = dyn_cast<cf::SwitchOp>(nested))
            visit(branch.getFlag());
          else if (!isa<cf::BranchOp>(nested))
            for (Value operand : nested->getOperands())
              visit(operand);
        });
        continue;
      }
      Value value = pendingValues.pop_back_val();
      if (Operation *definition = value.getDefiningOp()) {
        if (seenOps.insert(definition).second)
          pendingOps.push_back(definition);
        continue;
      }
      Block *block = cast<BlockArgument>(value).getOwner();
      visitBlock(block);
      unsigned index = cast<BlockArgument>(value).getArgNumber();
      for (auto it = block->pred_begin(); it != block->pred_end(); ++it) {
        Operation *term = (*it)->getTerminator();
        if (seenOps.insert(term).second)
          pendingOps.push_back(term);
        auto branch = dyn_cast<BranchOpInterface>(term);
        if (!branch)
          continue;
        Value incoming = branch.getSuccessorOperands(it.getSuccessorIndex())
                             .getForwardedOperands()[index];
        if (seenValues.insert(incoming).second)
          pendingValues.push_back(incoming);
      }
    }
    if (required)
      required->insert(seenOps.begin(), seenOps.end());
  }

private:
  const DenseMap<Operation *, Ranges> &reads;
  const DenseSet<Operation *> *privateReads;
  LocalStorageAnalysis locals;
  SmallVector<Operation *> privateStores;
  DenseMap<Block *, llvm::SetVector<Operation *>> controllers;
};

/// Source-written temporaries can be reconstructed independently in each
/// slice when every read follows a definition in this activation. Keep their
/// source-ordered versions in private SSA-promotable storage, and publish only
/// the selected stores. This permits a temporary to feed independent outputs
/// without merging them into one unit, while preserving saved snapshots.
DenseMap<Value, uint64_t>
getActivationTemporaryRoots(sim::SimFuncOp function,
                            const ActivationMemoryAnalysis &memory) {
  DenseSet<uint64_t> roots, readRoots;
  for (auto range : memory.getMayWrites())
    if (range.root < ActivationMemoryAnalysis::netRootTag)
      roots.insert(range.root);
  for (const auto &[op, ranges] : memory.getReads())
    for (auto range : ranges)
      readRoots.insert(range.root);
  for (auto range : memory.getLiveIns())
    roots.erase(range.root);
  for (const auto &[op, ranges] : memory.getReads())
    if (!isa<sim::SimRefLoadOp>(op))
      for (auto range : ranges)
        roots.erase(range.root);
  for (auto root : llvm::make_early_inc_range(roots))
    if (!readRoots.contains(root))
      roots.erase(root);
  DenseMap<Value, uint64_t> bases;
  if (roots.empty())
    return bases;
  auto facts = deriveHandleFacts(function);
  DenseMap<uint64_t, Type> rootTypes;
  for (auto [value, fact] : facts) {
    auto ref = dyn_cast<sim::RefType>(value.getType());
    bool entry =
        isa<BlockArgument>(value)
            ? cast<BlockArgument>(value).getOwner() ==
                  &function.getBody().front()
            : isa_and_nonnull<sim::SimContextStorageOp>(value.getDefiningOp());
    if (ref && entry && fact.descriptor && roots.contains(*fact.descriptor) &&
        !fact.dynamic && fact.low == 0 && fact.width == fact.rootWidth &&
        (sim::isAggregateType(ref.getElementType()) ||
         isa<IntegerType, sim::LogicType>(ref.getElementType()))) {
      auto [found, inserted] = rootTypes.try_emplace(*fact.descriptor, ref);
      if (!inserted && found->second != ref)
        roots.erase(*fact.descriptor);
      bases[value] = *fact.descriptor;
    }
  }
  auto reconstructible = [&](Value reference, auto &reconstructible) -> bool {
    if (auto found = bases.find(reference); found != bases.end())
      return roots.contains(found->second);
    Operation *definition = reference.getDefiningOp();
    if (!definition || !isMemoryEffectFree(definition) ||
        definition->getNumRegions())
      return false;
    bool hasReference = false;
    for (Value operand : definition->getOperands())
      if (isa<sim::RefType>(operand.getType())) {
        hasReference = true;
        if (!reconstructible(operand, reconstructible))
          return false;
      }
    return hasReference;
  };
  // A selected reference can name several source-written temporaries. They
  // can be reconstructed together only if every possible base remains a
  // candidate. Iterate to a fixed point so rejecting one base also rejects
  // references that select it through another candidate.
  for (bool changed = true; changed;) {
    changed = false;
    for (const auto *accesses : {&memory.getReads(), &memory.getWrites()})
      for (const auto &[op, ranges] : *accesses)
        for (auto range : ranges)
          if (roots.contains(range.root)) {
            Value reference;
            if (auto load = dyn_cast<sim::SimRefLoadOp>(op))
              reference = load.getReference();
            else if (auto store = dyn_cast<sim::SimRefStoreOp>(op))
              reference = store.getReference();
            if (!reference || !reconstructible(reference, reconstructible)) {
              roots.erase(range.root);
              changed = true;
            }
          }
  }
  for (auto [value, root] : llvm::make_early_inc_range(bases))
    if (!roots.contains(root))
      bases.erase(value);
  return bases;
}

OwningOpRef<sim::SimFuncOp>
cloneSliceWithTemporaries(const ActivationSlice &slice, IRMapping &mapping,
                          const DenseMap<Value, uint64_t> &temporaries);

/// The source activation already has a termination certificate. Slicing and
/// dialect canonicalization preserve it, even when they rotate a dead loop
/// into a different recurrence shape. A loop and its exit paths can therefore
/// be bypassed when they have no effects or escaping values and all paths
/// forward the same available values to their common postdominator.
bool removeEmptyFiniteLoop(sim::SimFuncOp function) {
  if (function.getBody().hasOneBlock())
    return false;
  DominanceInfo dominance;
  PostDominanceInfo postDominance;
  CFGLoopInfo loopInfo(dominance.getDomTree(&function.getBody()));
  auto preorder = loopInfo.getLoopsInPreorder();
  for (auto *loop : llvm::reverse(preorder)) {
    SmallVector<Block *> exits;
    loop->getExitBlocks(exits);
    if (exits.empty())
      continue;
    Block *join = exits.front();
    for (Block *exit : llvm::drop_begin(exits)) {
      join = postDominance.findNearestCommonDominator(join, exit);
      if (!join)
        break;
    }
    Block *header = loop->getHeader();
    if (!join || loop->contains(join))
      continue;
    DenseSet<Block *> members;
    SmallVector<Block *> blocks, pending{header};
    while (!pending.empty()) {
      Block *block = pending.pop_back_val();
      if (block == join || !members.insert(block).second)
        continue;
      blocks.push_back(block);
      llvm::append_range(pending, block->getSuccessors());
    }
    bool removable = true;
    std::optional<SmallVector<Value>> exitValues;
    for (Block *block : blocks) {
      auto escapes = [&](Value value) {
        return llvm::any_of(value.getUsers(), [&](Operation *user) {
          return !members.contains(user->getBlock());
        });
      };
      for (Operation &op : *block) {
        if (!isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp>(op) &&
            !wouldOpBeTriviallyDead(&op))
          removable = false;
        if (llvm::any_of(op.getResults(), escapes))
          removable = false;
      }
      if (llvm::any_of(block->getArguments(), escapes))
        removable = false;
      auto branch = dyn_cast<BranchOpInterface>(block->getTerminator());
      if (!branch || block->getNumSuccessors() == 0) {
        removable = false;
        continue;
      }
      for (auto [index, successor] : llvm::enumerate(block->getSuccessors())) {
        if (successor != join)
          continue;
        SmallVector<Value> operands(
            branch.getSuccessorOperands(index).getForwardedOperands());
        if (!llvm::all_of(operands, [&](Value value) {
              return !members.contains(value.getParentBlock()) &&
                     dominance.dominates(value, header->getTerminator());
            }))
          removable = false;
        if (exitValues && *exitValues != operands)
          removable = false;
        else
          exitValues = std::move(operands);
      }
    }
    if (!removable || !exitValues)
      continue;
    Operation *terminator = header->getTerminator();
    OpBuilder builder(terminator);
    cf::BranchOp::create(builder, terminator->getLoc(), join, *exitValues);
    terminator->erase();
    IRRewriter rewriter(function.getContext());
    (void)eraseUnreachableBlocks(rewriter, function.getBody());
    return true;
  }
  return false;
}

std::optional<Ranges>
getSliceReads(const ActivationSlice &slice,
              const DenseMap<Value, uint64_t> *temporaries = nullptr) {
  IRMapping mapping;
  auto copy = temporaries
                  ? cloneSliceWithTemporaries(slice, mapping, *temporaries)
                  : cloneActivationSlice(slice, &mapping);
  if (!copy)
    return std::nullopt;
  DenseMap<Operation *, Ranges> mappedReads;
  for (const auto &[op, ranges] : slice.activation->getMemory().getReads())
    mappedReads[mapping.lookup(op)] = ranges;
  LocalStorageAnalysis locals(*copy);
  Ranges reads;
  copy->walk([&](Operation *op) {
    if (isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimCallOp>(op) &&
        !locals.isLocalAccess(op))
      if (auto found = mappedReads.find(op); found != mappedReads.end())
        unionRanges(reads, found->second);
  });
  return reads;
}
} // namespace

std::optional<SmallVector<ActivationPublication>>
getActivationPublications(const ActivationRegionAnalysis &activation) {
  if (!activation.isValid() || activation.getMemory().hasMixedPrivateWrites())
    return std::nullopt;
  auto function = activation.getActivationFunction();
  const auto &memory = activation.getMemory();
  if (memory.hasValueDependencies()) {
    SmallVector<ActivationPublication> publications;
    function.walk([&](Operation *store) {
      auto found = memory.getPublications().find(store);
      if (found != memory.getPublications().end())
        for (const auto &lane : found->second)
          publications.push_back({store, lane.inputs, {lane.output}});
    });
    return publications;
  }
  ActivationLoadSlice slice(function, memory);
  SmallVector<ActivationPublication> publications;
  function.walk([&](Operation *store) {
    auto writes = memory.getWrites().find(store);
    // Accesses absent from the validated memory inventory are unreachable for
    // every proven induction context. The CFG retains their dead arms.
    if (writes == memory.getWrites().end())
      return;
    ActivationPublication publication{store, {}, writes->second};
    SmallVector<Operation *> loads;
    slice.collect(store, loads);
    for (Operation *load : loads) {
      auto reads = memory.getReads().find(load);
      if (reads != memory.getReads().end())
        unionRanges(publication.reads, reads->second);
    }
    publications.push_back(std::move(publication));
  });
  return publications;
}

std::optional<SmallVector<ActivationRegionStep>> getActivationPublicationOrder(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    SmallVectorImpl<ActivationRegionStep> *cycle) {
  if (cycle)
    cycle->clear();
  using Range = ActivationMemoryAnalysis::Range;
  SmallVector<ActivationRegionStep> steps;
  SmallVector<std::pair<unsigned, unsigned>> edges;
  DenseMap<uint64_t, SmallVector<std::pair<unsigned, Range>>> readers, writers;
  for (const auto *activation : activations) {
    auto publications = getActivationPublications(*activation);
    if (!publications)
      return std::nullopt;
    for (const auto &publication : *publications) {
      unsigned id = steps.size();
      steps.push_back({activation, publication.operation});
      for (const auto &range : publication.reads)
        readers[range.root].emplace_back(id, range);
      for (const auto &range : publication.writes)
        writers[range.root].emplace_back(id, range);
    }
  }
  for (const auto &[root, writes] : writers)
    for (const auto &[producer, write] : writes)
      for (const auto &[consumer, read] : readers[root])
        if (write.low < read.low + read.width &&
            read.low < write.low + write.width)
          edges.emplace_back(producer, consumer);
  return orderSteps(steps, std::move(edges), cycle);
}

namespace {
using InterleavingReads =
    DenseMap<Operation *, ActivationMemoryAnalysis::Ranges>;
using InterleavingReadCache =
    DenseMap<const ActivationRegionAnalysis *, InterleavingReads>;

using GuardBit = std::pair<uint64_t, uint64_t>;
using GuardCube = std::map<GuardBit, bool>;
using PulseGuards = SmallVector<GuardCube>;

std::optional<PulseGuards> combineGuards(ArrayRef<GuardCube> a,
                                         ArrayRef<GuardCube> b) {
  PulseGuards result;
  for (const auto &left : a)
    for (const auto &right : b) {
      GuardCube joined = left;
      bool compatible = true;
      for (const auto &[bit, value] : right) {
        auto [found, inserted] = joined.emplace(bit, value);
        compatible &= inserted || found->second == value;
      }
      if (joined.size() > 64)
        continue;
      if (compatible && !llvm::is_contained(result, joined)) {
        if (result.size() == 32)
          return result;
        result.push_back(std::move(joined));
      }
    }
  return result;
}

// Guard cubes are sufficient known-bit witnesses, not a two-state rewrite of
// four-state expressions. Unproved paths contribute no cube. A cohort input
// is stable only when its exclusive producer's final value can be resolved
// without a recursive value dependency or a read of its own publications.
class PulseGuardAnalysis {
public:
  using Resolve = std::function<std::optional<PulseGuards>(GuardBit, bool)>;
  PulseGuardAnalysis(const ActivationRegionAnalysis &activation,
                     const RangeSet &writes, Resolve resolve = {})
      : activation(activation), writes(writes), resolve(std::move(resolve)),
        dominance(activation.getActivationFunction()),
        postDominance(activation.getActivationFunction()) {
    ownWrites.unite(activation.getMemory().getMayWrites());
    for (auto scc =
             llvm::scc_begin(&activation.getActivationFunction().getBody());
         !scc.isAtEnd(); ++scc) {
      if (!scc.hasCycle())
        continue;
      acyclic = false;
      unsigned id = loops.size();
      for (Block *block : *scc)
        cyclicBlocks[block] = id;
      loops.emplace_back();
      auto &loop = loops.back();
      bool supported = true;
      for (Block *block : *scc) {
        for (Block *predecessor : block->getPredecessors())
          if (!cyclicBlocks.contains(predecessor) ||
              cyclicBlocks.lookup(predecessor) != id) {
            if (loop.entry && loop.entry != block)
              supported = false;
            loop.entry = block;
          }
        for (Block *next : block->getSuccessors())
          if (!cyclicBlocks.contains(next) || cyclicBlocks.lookup(next) != id) {
            if (loop.exit && loop.exit != next)
              supported = false;
            loop.exit = next;
          }
      }
      if (!supported)
        loop.entry = loop.exit = nullptr;
    }
  }
  bool hasAcyclicControl() const { return acyclic; }
  Value getUnprovedPredicate() const { return unprovedPredicate; }
  std::optional<PulseGuards> predicate(Value value, bool truth) {
    if (sim::getPackedWidth(value.getType()) != 1)
      return std::nullopt;
    return bitPredicate(value, 0, truth);
  }
  std::optional<PulseGuards> bitPredicate(Value value, unsigned bit,
                                          bool truth) {
    auto key = std::make_tuple(value, bit, unsigned(truth));
    auto found = cache.find(key);
    if (found != cache.end()) {
      if (!found->second && !unprovedPredicate)
        unprovedPredicate = value;
      return found->second;
    }
    if (depth == 128 || ++work > 4096)
      return std::nullopt;
    cache[key] = std::nullopt;
    ++depth;
    auto result = solve(value, bit, truth);
    --depth;
    if (!result && !unprovedPredicate)
      unprovedPredicate = value;
    cache[key] = result;
    return result;
  }
  PulseGuards edgeGuards(Operation *term, unsigned index) {
    if (pathDepth == 128 || ++work > 4096)
      return {};
    ++pathDepth;
    llvm::scope_exit restoreDepth([&] { --pathDepth; });
    if (auto found = cyclicBlocks.find(term->getBlock());
        found != cyclicBlocks.end()) {
      const auto &loop = loops[found->second];
      if (!loop.entry || term->getSuccessor(index) != loop.exit)
        return {};
      // Valid activations already have a finite-control-flow proof. A
      // single-entry, single-exit loop therefore reaches its common exit
      // whenever its entry executes. This contracts only reachability;
      // values and publications inside the loop remain unproved.
      PulseGuards result;
      for (auto it = loop.entry->pred_begin(); it != loop.entry->pred_end();
           ++it)
        if (auto predecessor = cyclicBlocks.find(*it);
            predecessor == cyclicBlocks.end() ||
            predecessor->second != found->second)
          if (!append(result, edgeGuards((*it)->getTerminator(),
                                         it.getSuccessorIndex())))
            return {};
      return result;
    }
    PulseGuards guards = pathGuards(term->getBlock());
    auto condition = edgeCondition(term, index);
    auto combined =
        condition ? combineGuards(guards, *condition) : std::nullopt;
    return combined.value_or(PulseGuards{});
  }
  std::optional<PulseGuards> edgeCondition(Operation *term, unsigned index) {
    if (isa<cf::BranchOp>(term))
      return PulseGuards{GuardCube{}};
    if (auto branch = dyn_cast<cf::CondBranchOp>(term))
      return predicate(branch.getCondition(), index == 0);
    auto choice = dyn_cast<cf::SwitchOp>(term);
    if (!choice)
      return std::nullopt;
    PulseGuards result{GuardCube{}};
    if (auto cases = choice.getCaseValues())
      for (auto [lane, fixed] : llvm::enumerate(cases->getValues<APInt>())) {
        if (index && lane + 1 != index)
          continue;
        auto condition = bitEquality(choice.getFlag(), fixed, index != 0);
        auto joined =
            condition ? combineGuards(result, *condition) : std::nullopt;
        if (!joined)
          return std::nullopt;
        result = std::move(*joined);
      }
    return result;
  }
  PulseGuards pathGuards(Block *block) {
    if (cyclicBlocks.contains(block) || pathDepth == 128 || ++work > 4096)
      return {};
    if (auto found = blockGuards.find(block); found != blockGuards.end())
      return found->second;
    ++pathDepth;
    llvm::scope_exit restoreDepth([&] { --pathDepth; });
    blockGuards[block] = {};
    if (block == &activation.getActivationFunction().getBody().front())
      return blockGuards[block] = {GuardCube{}};
    if (auto *node = dominance.getNode(block); node && node->getIDom())
      if (Block *before = node->getIDom()->getBlock();
          before && !cyclicBlocks.contains(before) &&
          postDominance.postDominates(block, before))
        // A completed finite diamond does not restrict reachability of its
        // common join. Normalize that control fact before expanding branch
        // predicates, without speculating or rereading any of their values.
        return blockGuards[block] = pathGuards(before);
    PulseGuards result;
    for (auto it = block->pred_begin(); it != block->pred_end(); ++it) {
      auto guards = edgeGuards((*it)->getTerminator(), it.getSuccessorIndex());
      if (!append(result, guards))
        return {};
    }
    return blockGuards[block] = result;
  }
  static bool append(PulseGuards &into, ArrayRef<GuardCube> from) {
    for (const auto &cube : from)
      if (!llvm::any_of(into, [&](const GuardCube &existing) {
            return llvm::all_of(existing, [&](const auto &bit) {
              auto found = cube.find(bit.first);
              return found != cube.end() && found->second == bit.second;
            });
          })) {
        llvm::erase_if(into, [&](const GuardCube &existing) {
          return llvm::all_of(cube, [&](const auto &bit) {
            auto found = existing.find(bit.first);
            return found != existing.end() && found->second == bit.second;
          });
        });
        if (into.size() == 32)
          continue;
        into.push_back(cube);
      }
    // These are sufficient witnesses, not a may-execute summary. Retaining a
    // bounded subset remains sound; losing a witness can only miss a possible
    // livelock. Never use this bounded DNF to remove a dependence or event.
    return true;
  }

  /// A may-write envelope does not prove that a publication occurs. In
  /// particular an invalid dynamic index writes nothing (11.5.1), even when
  /// its envelope has exactly the width of the stored scalar.
  bool hasExactStoreTarget(sim::SimRefStoreOp store, const Range &range) {
    if (!store)
      return false;
    if (!handleFacts)
      handleFacts = HandleDataflowAnalysis(activation.getActivationFunction())
                        .derive(activation.getActivationFunction());
    Value reference = store.getReference();
    auto found = handleFacts->find(reference);
    auto span = sim::getProvenanceSpan(reference.getType());
    if (found == handleFacts->end() || !span)
      return false;
    const auto &fact = found->second;
    if (!fact.descriptor || fact.dynamic || fact.width != *span ||
        fact.low > fact.rootWidth || fact.width > fact.rootWidth - fact.low)
      return false;
    auto root =
        ActivationMemoryAnalysis::getRoot(fact.resource, *fact.descriptor);
    return root && range == Range{*root, fact.low, fact.width};
  }

private:
  std::optional<PulseGuards> inputBit(Range range, bool truth) {
    if (!ownWrites.intersectWith({range}).empty())
      return std::nullopt;
    if (!writes.intersectWith({range}).empty())
      return resolve ? resolve({range.root, range.low}, truth) : std::nullopt;
    return PulseGuards{GuardCube{{{range.root, range.low}, truth}}};
  }
  std::optional<PulseGuards> referencePredicate(Value reference, uint64_t bit,
                                                bool truth) {
    if (depth == 128 || ++work > 4096)
      return std::nullopt;
    ++depth;
    llvm::scope_exit restoreDepth([&] { --depth; });
    if (!handleFacts)
      handleFacts = HandleDataflowAnalysis(activation.getActivationFunction())
                        .derive(activation.getActivationFunction());
    auto found = handleFacts->find(reference);
    if (found != handleFacts->end() && found->second.descriptor &&
        !found->second.dynamic && bit < found->second.width) {
      const auto &fact = found->second;
      auto root =
          ActivationMemoryAnalysis::getRoot(fact.resource, *fact.descriptor);
      return root ? inputBit({*root, fact.low + bit, 1}, truth) : std::nullopt;
    }
    if (auto extract = reference.getDefiningOp<sim::SimRefExtractOp>())
      return referencePredicate(extract.getInput(), bit + extract.getLowBit(),
                                truth);
    if (auto field = reference.getDefiningOp<sim::SimRefSubelementOp>()) {
      Type type = field.getInput().getType().getElementType();
      uint64_t offset = 0;
      for (int64_t index : field.getIndices()) {
        auto child = index >= 0 && uint64_t(index) <= UINT_MAX
                         ? sim::getAggregateProvenanceSubelement(type, index)
                         : std::nullopt;
        if (!child || child->first > UINT64_MAX - offset)
          return std::nullopt;
        offset += child->first;
        type = sim::getAggregateElementType(type, index);
      }
      return referencePredicate(field.getInput(), bit + offset, truth);
    }
    if (auto element = reference.getDefiningOp<sim::SimRefArrayElementOp>()) {
      Type type = element.getInput().getType().getElementType();
      auto bounds =
          TypeSwitch<Type, std::optional<std::pair<int64_t, int64_t>>>(type)
              .Case<sim::PackedArrayType, sim::UnpackedArrayType>(
                  [](auto array) {
                    return std::pair{array.getLeft(), array.getRight()};
                  })
              .Default(std::nullopt);
      auto width = sim::getPackedWidth(element.getIndex().getType());
      unsigned count = sim::getAggregateNumElements(type);
      if (!bounds || !width || *width > 128 || count > 16)
        return std::nullopt;
      PulseGuards result;
      for (unsigned ordinal = 0; ordinal < count; ++ordinal) {
        int64_t logical = bounds->first <= bounds->second
                              ? bounds->first + ordinal
                              : bounds->first - ordinal;
        auto child = sim::getAggregateProvenanceSubelement(type, ordinal);
        if (!child || bit >= child->second)
          continue;
        auto index = bitEquality(element.getIndex(),
                                 APInt(*width, uint64_t(logical), true), true);
        auto value =
            referencePredicate(element.getInput(), child->first + bit, truth);
        auto joined =
            index && value ? combineGuards(*index, *value) : std::nullopt;
        if (joined && !append(result, *joined))
          return std::nullopt;
      }
      return result;
    }
    return std::nullopt;
  }
  std::optional<PulseGuards> bitEquality(Value input, const APInt &fixed,
                                         bool match) {
    if (fixed.getBitWidth() > 128)
      return std::nullopt;
    PulseGuards result = match ? PulseGuards{GuardCube{}} : PulseGuards{};
    for (unsigned lane = 0; lane < fixed.getBitWidth(); ++lane) {
      auto part = bitPredicate(input, lane, bool(fixed[lane]) == match);
      if (!part && match)
        return std::nullopt;
      if (match) {
        auto joined = combineGuards(result, *part);
        if (!joined)
          return std::nullopt;
        result = std::move(*joined);
      } else if (part && !append(result, *part))
        return std::nullopt;
    }
    return result;
  }
  std::optional<PulseGuards> truthPredicate(Value value, bool truth) {
    auto width = sim::getPackedWidth(value.getType());
    if (!width || *width > 64)
      return std::nullopt;
    PulseGuards result = truth ? PulseGuards{} : PulseGuards{GuardCube{}};
    for (unsigned bit = 0; bit < *width; ++bit) {
      auto part = bitPredicate(value, bit, truth);
      if (!part && !truth)
        return std::nullopt;
      if (truth) {
        if (part && !append(result, *part))
          return std::nullopt;
      } else {
        auto joined = combineGuards(result, *part);
        if (!joined)
          return std::nullopt;
        result = std::move(*joined);
      }
    }
    return result;
  }
  std::optional<PulseGuards> solve(Value value, unsigned bit, bool truth) {
    auto width = sim::getPackedWidth(value.getType());
    if (!width || bit >= *width)
      return std::nullopt;
    Operation *op = value.getDefiningOp();
    if (!op) {
      auto argument = dyn_cast<BlockArgument>(value);
      if (!argument || cyclicBlocks.contains(argument.getOwner()) ||
          argument.getOwner() ==
              &activation.getActivationFunction().getBody().front())
        return std::nullopt;
      PulseGuards result;
      for (auto it = argument.getOwner()->pred_begin();
           it != argument.getOwner()->pred_end(); ++it) {
        auto term = dyn_cast<BranchOpInterface>((*it)->getTerminator());
        if (!term)
          continue;
        auto incoming = term.getSuccessorOperands(it.getSuccessorIndex());
        if (incoming.isOperandProduced(argument.getArgNumber()))
          continue;
        auto part = bitPredicate(incoming[argument.getArgNumber()], bit, truth);
        auto guards = edgeGuards(term, it.getSuccessorIndex());
        auto joined = part ? combineGuards(guards, *part) : std::nullopt;
        if (joined && !append(result, *joined))
          return std::nullopt;
      }
      return result;
    }
    if (isa<arith::ConstantOp, sim::SimLogicConstantOp>(op)) {
      auto constant = op->getAttrOfType<IntegerAttr>("value");
      auto unknown = op->getAttrOfType<IntegerAttr>("unknown");
      if (!constant || (unknown && unknown.getValue()[bit]))
        return std::nullopt;
      return bool(constant.getValue()[bit]) == truth ? PulseGuards{GuardCube{}}
                                                     : PulseGuards{};
    }
    if (auto load = dyn_cast<sim::SimRefLoadOp>(op))
      return referencePredicate(load.getReference(), bit, truth);
    if (isa<sim::SimLogicIsTrueOp>(op))
      return truthPredicate(op->getOperand(0), truth);
    if (isa<sim::SimLogicFromBitsOp, sim::SimLogicToBitsOp,
            sim::SimPackedFlattenOp, sim::SimPackedUnflattenOp>(op))
      return bitPredicate(op->getOperand(0), bit, truth);
    if (auto extract = dyn_cast<sim::SimLogicExtractOp>(op))
      return bitPredicate(extract.getInput(), bit + extract.getLowBit(), truth);
    if (auto extract = dyn_cast<sim::SimAggregateExtractOp>(op)) {
      auto field = sim::getAggregateProvenanceSubelement(
          extract.getInput().getType(), extract.getIndex());
      return field ? bitPredicate(extract.getInput(), bit + field->first, truth)
                   : std::nullopt;
    }
    if (auto resize = dyn_cast<sim::SimLogicResizeOp>(op)) {
      unsigned input = resize.getInput().getType().getWidth();
      if (bit < input)
        return bitPredicate(resize.getInput(), bit, truth);
      if (resize.getIsSigned())
        return bitPredicate(resize.getInput(), input - 1, truth);
      return truth ? PulseGuards{} : PulseGuards{GuardCube{}};
    }
    if (isa<arith::ExtUIOp, arith::ExtSIOp, arith::TruncIOp>(op)) {
      Value input = op->getOperand(0);
      unsigned inputWidth = cast<IntegerType>(input.getType()).getWidth();
      if (bit < inputWidth)
        return bitPredicate(input, bit, truth);
      if (isa<arith::ExtSIOp>(op))
        return bitPredicate(input, inputWidth - 1, truth);
      return truth ? PulseGuards{} : PulseGuards{GuardCube{}};
    }
    if (auto unary = dyn_cast<sim::SimLogicUnaryOp>(op)) {
      if (unary.isBitwiseNegation())
        return bitPredicate(unary.getInput(), bit, !truth);
      if (unary.getKind() == sim::UnaryKind::LogicalNot)
        return truthPredicate(unary.getInput(), !truth);
    }
    if (auto reduction = dyn_cast<sim::SimLogicReductionOp>(op))
      if (reduction.getKind() == sim::ReductionKind::Or)
        return truthPredicate(reduction.getInput(), truth);
    if (auto select = dyn_cast<arith::SelectOp>(op)) {
      PulseGuards result;
      for (bool take : {false, true}) {
        auto condition = predicate(select.getCondition(), take);
        auto part = bitPredicate(
            take ? select.getTrueValue() : select.getFalseValue(), bit, truth);
        auto joined =
            condition && part ? combineGuards(*condition, *part) : std::nullopt;
        if (joined && !append(result, *joined))
          return std::nullopt;
      }
      return result;
    }
    if (auto compare = dyn_cast<sim::SimLogicCompareOp>(op)) {
      bool equal = compare.getKind() == sim::CompareKind::Eq ||
                   compare.getKind() == sim::CompareKind::CaseEq;
      bool unequal = compare.getKind() == sim::CompareKind::Ne ||
                     compare.getKind() == sim::CompareKind::CaseNe;
      if (!equal && !unequal)
        return std::nullopt;
      Value input = compare.getLhs(), fixed = compare.getRhs();
      if (!fixed.getDefiningOp<sim::SimLogicConstantOp>())
        std::swap(input, fixed);
      auto constant = fixed.getDefiningOp<sim::SimLogicConstantOp>();
      if (!constant || !constant.getUnknown().isZero() ||
          constant.getValue().getBitWidth() > 64)
        return std::nullopt;
      return bitEquality(input, constant.getValue(), truth == equal);
    }
    if (auto compare = dyn_cast<arith::CmpIOp>(op)) {
      bool equal = compare.getPredicate() == arith::CmpIPredicate::eq;
      if (!equal && compare.getPredicate() != arith::CmpIPredicate::ne)
        return std::nullopt;
      Value input = compare.getLhs(), fixed = compare.getRhs();
      if (!fixed.getDefiningOp<arith::ConstantOp>())
        std::swap(input, fixed);
      auto constant = fixed.getDefiningOp<arith::ConstantOp>();
      auto integer =
          constant ? dyn_cast<IntegerAttr>(constant.getValue()) : IntegerAttr{};
      return integer ? bitEquality(input, integer.getValue(), truth == equal)
                     : std::nullopt;
    }
    if (auto binary = dyn_cast<arith::XOrIOp>(op)) {
      PulseGuards result;
      for (bool leftBit : {false, true}) {
        auto left = bitPredicate(binary.getLhs(), bit, leftBit);
        auto right = bitPredicate(binary.getRhs(), bit, leftBit != truth);
        auto joined =
            left && right ? combineGuards(*left, *right) : std::nullopt;
        if (joined)
          append(result, *joined);
      }
      return result;
    }
    bool conjunction = isa<arith::AndIOp>(op);
    bool disjunction = isa<arith::OrIOp>(op);
    if (auto binary = dyn_cast<sim::SimLogicBinaryOp>(op)) {
      conjunction = binary.getKind() == sim::BinaryKind::And;
      disjunction = binary.getKind() == sim::BinaryKind::Or;
    }
    bool logical = isa<sim::SimLogicLogicalOp>(op);
    if (auto logicalOp = dyn_cast<sim::SimLogicLogicalOp>(op)) {
      conjunction = logicalOp.getKind() == sim::LogicalKind::And;
      disjunction = logicalOp.getKind() == sim::LogicalKind::Or;
    }
    if (!conjunction && !disjunction)
      return std::nullopt;
    auto left = logical ? truthPredicate(op->getOperand(0), truth)
                        : bitPredicate(op->getOperand(0), bit, truth);
    auto right = logical ? truthPredicate(op->getOperand(1), truth)
                         : bitPredicate(op->getOperand(1), bit, truth);
    if (truth == conjunction)
      return left && right ? combineGuards(*left, *right) : std::nullopt;
    PulseGuards result = left.value_or(PulseGuards{});
    return !right || append(result, *right)
               ? std::optional<PulseGuards>(std::move(result))
               : std::nullopt;
  }
  const ActivationRegionAnalysis &activation;
  const RangeSet &writes;
  RangeSet ownWrites;
  Resolve resolve;
  DominanceInfo dominance;
  PostDominanceInfo postDominance;
  unsigned work = 0, depth = 0;
  unsigned pathDepth = 0;
  bool acyclic = true;
  struct Loop {
    Block *entry = nullptr, *exit = nullptr;
  };
  SmallVector<Loop> loops;
  DenseMap<Block *, unsigned> cyclicBlocks;
  std::optional<HandleFacts> handleFacts;
  Value unprovedPredicate;
  DenseMap<std::tuple<Value, unsigned, unsigned>, std::optional<PulseGuards>>
      cache;
  DenseMap<Block *, PulseGuards> blockGuards;
};

// Final values are evaluated only on demand for bits used by another owner's
// pulse guard. Backward CFG summaries distinguish paths with no further write
// from paths whose final value is already determined. This retains last-write
// semantics without expanding the CFG into exponentially many paths.
class PulseFinalValues {
public:
  PulseFinalValues(ArrayRef<const ActivationRegionAnalysis *> activations,
                   const RangeSet &writes)
      : activations(activations) {
    for (const auto *activation : activations)
      guards.push_back(std::make_unique<PulseGuardAnalysis>(
          *activation, writes,
          [&](GuardBit bit, bool truth) { return get(bit, truth); }));
  }
  std::optional<PulseGuards> get(GuardBit bit, bool truth) {
    auto key = std::make_pair(bit, truth);
    if (auto found = values.find(key); found != values.end())
      return found->second;
    values[key] = std::nullopt; // Reject recursive final-value equations.
    unsigned owner = UINT_MAX;
    Range target{bit.first, bit.second, 1};
    for (auto [index, activation] : llvm::enumerate(activations)) {
      RangeSet writes;
      writes.unite(activation->getMemory().getMayWrites());
      if (!writes.intersectWith({target}).empty()) {
        if (owner != UINT_MAX)
          return std::nullopt;
        owner = index;
      }
    }
    if (owner == UINT_MAX || values.size() > 128 ||
        !guards[owner]->hasAcyclicControl())
      return std::nullopt;
    struct Summary {
      PulseGuards holds, value;
    };
    DenseMap<Block *, Summary> summaries;
    unsigned work = 0, depth = 0;
    auto visit = [&](Block *block, auto &visit) -> Summary {
      if (auto found = summaries.find(block); found != summaries.end())
        return found->second;
      summaries[block] = {};
      if (depth == 128 || ++work > 4096)
        return {};
      ++depth;
      llvm::scope_exit restoreDepth([&] { --depth; });
      Summary result;
      Operation *term = block->getTerminator();
      if (isa<sim::SimReturnOp>(term))
        result.holds = {GuardCube{}};
      for (auto [index, next] : llvm::enumerate(term->getSuccessors())) {
        // Use the branch predicate, not its complete incoming path: the
        // backward summary will supply that path at its predecessor.
        auto condition = guards[owner]->edgeCondition(term, index);
        if (!condition)
          continue;
        auto suffix = visit(next, visit);
        auto holds = combineGuards(*condition, suffix.holds);
        auto value = combineGuards(*condition, suffix.value);
        if (!holds || !value ||
            !PulseGuardAnalysis::append(result.holds, *holds) ||
            !PulseGuardAnalysis::append(result.value, *value))
          return {};
      }
      const auto &memory = activations[owner]->getMemory();
      for (Operation &op : llvm::reverse(block->without_terminator())) {
        auto found = memory.getWrites().find(&op);
        if (found == memory.getWrites().end())
          continue;
        RangeSet writes;
        writes.unite(found->second);
        if (writes.intersectWith({target}).empty())
          continue;
        if (found->second.size() != 1 || result.holds.empty()) {
          if (found->second.size() != 1)
            return Summary{};
          continue;
        }
        auto range = found->second.front();
        if (!guards[owner]->hasExactStoreTarget(
                dyn_cast<sim::SimRefStoreOp>(op), range))
          // An overlapping ambiguous write can supersede an earlier exact
          // value. It must not be skipped to invent a final-value witness.
          return Summary{};
        auto stored = guards[owner]->bitPredicate(
            ActivationMemoryAnalysis::getStoredValue(&op),
            bit.second - range.low, truth);
        auto value =
            stored ? combineGuards(result.holds, *stored) : std::nullopt;
        if (value && !PulseGuardAnalysis::append(result.value, *value))
          return Summary{};
        result.holds.clear();
      }
      return summaries[block] = result;
    };
    auto result = visit(
        &activations[owner]->getActivationFunction().getBody().front(), visit);
    return values[key] = result.value;
  }
  PulseGuardAnalysis &getGuards(unsigned owner) { return *guards[owner]; }

private:
  ArrayRef<const ActivationRegionAnalysis *> activations;
  SmallVector<std::unique_ptr<PulseGuardAnalysis>> guards;
  std::map<std::pair<GuardBit, bool>, std::optional<PulseGuards>> values;
};

bool mayHavePulseCycle(ArrayRef<const ActivationRegionAnalysis *> activations) {
  if (activations.size() < 2 || activations.size() > 8)
    return false;
  unsigned pulsing = 0;
  for (const auto *activation : activations) {
    if (!activation->isValid() || !activation->getWatchedRanges())
      return false;
    pulsing += !activation->getMemory().getRepeatedWrites().empty() &&
               activation->getActivationFunction().getEntryKind() ==
                   sim::EntryKind::AlwaysComb;
  }
  return pulsing >= 2;
}

bool hasPossiblePulseCycle(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    ActivationRearmPlan::Trace trace = {}) {
  if (!mayHavePulseCycle(activations))
    return false;
  using Range = ActivationMemoryAnalysis::Range;
  struct Pulse {
    Range range;
    GuardCube guard;
  };
  SmallVector<SmallVector<Pulse>> pulses(activations.size());
  RangeSet cohortWrites;
  for (const auto *activation : activations)
    cohortWrites.unite(activation->getMemory().getMayWrites());
  RangeSet watched;
  for (const auto *activation : activations)
    watched.unite(*activation->getWatchedRanges());
  PulseFinalValues finalValues(activations, cohortWrites);
  for (auto [owner, activation] : llvm::enumerate(activations)) {
    if (activation->getActivationFunction().getEntryKind() !=
            sim::EntryKind::AlwaysComb ||
        activation->getMemory().getRepeatedWrites().empty())
      continue;
    struct Store {
      Range range;
      Value value;
      std::optional<APInt> bits, unknown;
      PulseGuards guards;
    };
    auto &guardAnalysis = finalValues.getGuards(owner);
    SmallVector<Store> stores;
    activation->getActivationFunction().walk([&, activation = activation](
                                                 sim::SimRefStoreOp store) {
      const auto &writes = activation->getMemory().getWrites();
      auto found = writes.find(store);
      if (found == writes.end() || found->second.size() != 1 ||
          watched.intersectWith(found->second).empty())
        return;
      Range range = found->second.front();
      if (!guardAnalysis.hasExactStoreTarget(store, range))
        return;
      const auto *node = activation->getNode(store);
      PulseGuards guards = node && !node->isRegion()
                               ? PulseGuards{GuardCube{}}
                               : guardAnalysis.pathGuards(store->getBlock());
      if (trace) {
        trace(activation, store.getValue(),
              guards.empty() ? "unproved store guard" : "proved store guard");
        if (guards.empty() && guardAnalysis.getUnprovedPredicate())
          trace(activation, guardAnalysis.getUnprovedPredicate(),
                "unproved predicate");
      }
      if (guards.empty())
        return;
      Store fact{range, store.getValue(), std::nullopt, std::nullopt,
                 std::move(guards)};
      Operation *definition = store.getValue().getDefiningOp();
      if (definition &&
          isa<arith::ConstantOp, sim::SimLogicConstantOp>(definition)) {
        auto value = definition->getAttrOfType<IntegerAttr>("value");
        auto unknown = definition->getAttrOfType<IntegerAttr>("unknown");
        if (value && value.getValue().getBitWidth() == range.width) {
          fact.bits = value.getValue();
          fact.unknown = unknown ? unknown.getValue() : APInt(range.width, 0);
        }
      }
      if (fact.bits || range.width == 1)
        stores.push_back(std::move(fact));
    });
    llvm::sort(stores, [](const auto &a, const auto &b) {
      return std::tie(a.range.root, a.range.low, a.range.width) <
             std::tie(b.range.root, b.range.low, b.range.width);
    });
    size_t comparisons = 0;
    for (unsigned i = 0; i < stores.size(); ++i)
      for (unsigned j = i + 1;
           j < stores.size() && stores[j].range == stores[i].range; ++j) {
        if (++comparisons > std::max(size_t{65536}, stores.size() * 64))
          return false;
        auto guards = combineGuards(stores[i].guards, stores[j].guards);
        if (!guards)
          return false;
        APInt different(stores[i].range.width, 0);
        if (stores[i].bits && stores[j].bits)
          different = (*stores[j].bits ^ *stores[i].bits) |
                      (*stores[j].unknown ^ *stores[i].unknown);
        else {
          PulseGuards unequal;
          for (bool first : {false, true}) {
            auto left = guardAnalysis.predicate(stores[i].value, first);
            auto right = guardAnalysis.predicate(stores[j].value, !first);
            auto condition =
                left && right ? combineGuards(*left, *right) : std::nullopt;
            auto witness =
                condition ? combineGuards(*guards, *condition) : std::nullopt;
            if (witness && !PulseGuardAnalysis::append(unequal, *witness))
              return false;
          }
          guards = std::move(unequal);
          different.setBit(0);
        }
        for (unsigned bit = 0; bit < different.getBitWidth();) {
          if (!different[bit]) {
            ++bit;
            continue;
          }
          unsigned begin = bit++;
          while (bit < different.getBitWidth() && different[bit])
            ++bit;
          for (const auto &guard : *guards) {
            if (pulses[owner].size() == 4096)
              return false;
            pulses[owner].push_back({{stores[i].range.root,
                                      stores[i].range.low + begin, bit - begin},
                                     guard});
          }
        }
      }
  }

  SmallVector<SmallVector<PulseGuards>> edges(
      activations.size(), SmallVector<PulseGuards>(activations.size()));
  for (unsigned from = 0; from < activations.size(); ++from)
    for (unsigned to = 0; to < activations.size(); ++to)
      if (from != to) {
        RangeSet watches;
        watches.unite(*activations[to]->getWatchedRanges());
        for (const auto &pulse : pulses[from])
          if (!watches.intersectWith({pulse.range}).empty())
            if (!PulseGuardAnalysis::append(edges[from][to], {pulse.guard}))
              return false;
      }
  // One satisfiable directed cycle is enough. Requiring every member of
  // an observer-closed cohort to pulse would miss a loop accompanied by a
  // passive observer, or mutually exclusive LOAD and STORE pulse cycles.
  struct Witness {
    GuardCube guard;
    unsigned last;
    uint8_t visited;
  };
  unsigned work = 0;
  for (unsigned root = 0; root < activations.size(); ++root) {
    SmallVector<Witness> pending{{{}, root, uint8_t(1u << root)}};
    while (!pending.empty()) {
      Witness witness = pending.pop_back_val();
      for (unsigned to = root; to < activations.size(); ++to) {
        if (to != root && (witness.visited & (1u << to)))
          continue;
        for (const auto &cube : edges[witness.last][to]) {
          if (++work > 4096)
            return false;
          auto joined = combineGuards({witness.guard}, {cube});
          if (!joined || joined->empty())
            continue;
          if (to == root)
            return true;
          pending.push_back({std::move(joined->front()), to,
                             uint8_t(witness.visited | (1u << to))});
        }
      }
    }
  }

  return false;
}

std::optional<ActivationSchedule> buildActivationRegionSchedule(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    const InterleavingReadCache *demandedReads = nullptr,
    bool bounded = false) {
  using Range = ActivationMemoryAnalysis::Range;
  struct Access {
    unsigned step;
    Range range;
    schedule::SourceOwnerAttr owner;
  };
  ActivationSchedule result;
  auto &steps = result.nodes;
  auto edge = [&](unsigned source, unsigned target,
                  ActivationSchedule::DependencyKind kind) {
    result.dependencies.push_back({source, target, kind});
  };
  struct Interval {
    Access access;
    bool write;
  };
  SmallVector<Interval> intervals;
  for (const auto *activation : activations) {
    if (!activation->isValid())
      return std::nullopt;
    result.sensitivityEvents.push_back(activation->getSuspension());
    const auto &memory = activation->getMemory();
    const auto *selectedReads = &memory.getReads();
    if (demandedReads) {
      auto refined = demandedReads->find(activation);
      if (refined != demandedReads->end())
        selectedReads = &refined->second;
    }
    bool hasOwners = true;
    activation->getActivationFunction().walk([&](Operation *op) {
      if ((memory.getReads().contains(op) || memory.getWrites().contains(op)) &&
          !schedule::get<schedule::Field::EvalSourceOwner>(op))
        hasOwners = false;
    });
    unsigned first = steps.size();
    DenseMap<schedule::SourceOwnerAttr, unsigned> previous;
    for (const auto &node : activation->getNodes()) {
      unsigned id = steps.size();
      steps.push_back({activation, node.operation});
      llvm::SetVector<schedule::SourceOwnerAttr> owners;
      if (!hasOwners)
        owners.insert({});
      node.walk([&](Operation *op) {
        auto owner = hasOwners
                         ? schedule::get<schedule::Field::EvalSourceOwner>(op)
                         : schedule::SourceOwnerAttr{};
        if (owner)
          owners.insert(owner);
        auto record = [&](const auto &accesses, bool write) {
          auto found = accesses.find(op);
          if (found != accesses.end())
            for (Range range : found->second)
              if (range.width)
                intervals.push_back({{id, range, owner}, write});
        };
        record(*selectedReads, false);
        record(memory.getWrites(), true);
      });
      // Fusion does not create source-order relations between the original
      // processes. Preserve each owner's order, including owners sharing a
      // unit. Incomplete provenance keeps the whole-body chain.
      for (auto owner : owners) {
        auto found = previous.find(owner);
        if (found != previous.end())
          edge(found->second, id,
               ActivationSchedule::DependencyKind::SourceOrder);
        previous[owner] = id;
      }
    }
    // Pure SSA producers may have been shared by CSE. Their def-use edges are
    // required independently of publication provenance, including a region's
    // join arguments and values captured by nested operations.
    auto nodeIndex = [&](const ActivationRegionAnalysis::Node *node) {
      return first + unsigned(node - activation->getNodes().data());
    };
    for (const auto &node : activation->getNodes()) {
      unsigned consumer = nodeIndex(&node);
      node.walk([&](Operation *op) {
        for (Value operand : op->getOperands())
          if (const auto *producer = activation->getDefiningNode(operand);
              producer && producer != &node)
            edge(nodeIndex(producer), consumer,
                 ActivationSchedule::DependencyKind::SSA);
      });
    }
  }
  // Half-open intervals: end events precede starts at the same bit. Compare
  // only simultaneously live intervals on the same root, rather than every
  // read/write pair of a large aggregate. Sorting the resulting dependencies
  // below retains deterministic node order independently of set iteration.
  struct Endpoint {
    uint64_t root, bit;
    unsigned interval;
    bool start;
  };
  SmallVector<Endpoint> endpoints;
  endpoints.reserve(intervals.size() * 2);
  for (auto [id, interval] : llvm::enumerate(intervals)) {
    const Range &range = interval.access.range;
    if (range.low > UINT64_MAX - range.width)
      return std::nullopt;
    endpoints.push_back({range.root, range.low, unsigned(id), true});
    endpoints.push_back(
        {range.root, range.low + range.width, unsigned(id), false});
  }
  llvm::sort(endpoints, [](const Endpoint &a, const Endpoint &b) {
    return std::tie(a.root, a.bit, a.start, a.interval) <
           std::tie(b.root, b.bit, b.start, b.interval);
  });
  std::set<unsigned> readers, writers;
  // Dense overlapping accesses have quadratic output even with an index.
  // Bound both comparisons and stored edges by the input size. Exhaustion
  // means an unavailable proof, never permission to cut a dependency.
  size_t comparisons = 0;
  size_t budget = std::max(size_t{65536}, intervals.size() * 64);
  auto connectRead = [&](const Access &write, const Access &read) {
    if (write.step == read.step)
      return;
    if (steps[write.step].activation != steps[read.step].activation ||
        write.owner != read.owner)
      edge(write.step, read.step, ActivationSchedule::DependencyKind::Value);
    else
      edge(std::min(write.step, read.step), std::max(write.step, read.step),
           ActivationSchedule::DependencyKind::Snapshot);
  };
  for (const Endpoint &point : endpoints) {
    const Interval &current = intervals[point.interval];
    auto &active = current.write ? writers : readers;
    if (!point.start) {
      active.erase(point.interval);
      continue;
    }
    for (unsigned id : writers) {
      if (++comparisons > budget && bounded)
        return std::nullopt;
      const Access &write = intervals[id].access;
      if (!current.write)
        connectRead(write, current.access);
      else if (write.step != current.access.step &&
               write.owner != current.access.owner &&
               steps[write.step].activation ==
                   steps[current.access.step].activation)
        edge(std::min(write.step, current.access.step),
             std::max(write.step, current.access.step),
             ActivationSchedule::DependencyKind::Publication);
    }
    if (current.write)
      for (unsigned id : readers) {
        if (++comparisons > budget && bounded)
          return std::nullopt;
        connectRead(current.access, intervals[id].access);
      }
    active.insert(point.interval);
  }
  if (!buildComponents(result))
    return std::nullopt;
  return result;
}

std::optional<SmallVector<ActivationRegionStep>> minimumHandoffOrder(
    const ActivationSchedule &schedule,
    ArrayRef<const ActivationRegionAnalysis *> activations,
    std::optional<unsigned> &handoffs,
    SmallVectorImpl<const ActivationRegionAnalysis *> *held = nullptr,
    bool wholeBodies = false,
    SmallVectorImpl<ActivationRegionStep> *preemptions = nullptr,
    SmallVectorImpl<const ActivationRegionAnalysis *> *runs = nullptr) {
  unsigned count = activations.size(), nodes = schedule.nodes.size();
  if (count > 8)
    return std::nullopt;
  DenseMap<const ActivationRegionAnalysis *, unsigned> owners;
  SmallVector<SmallVector<unsigned>> sequences(count);
  SmallVector<unsigned> ownerOf(nodes), position(nodes);
  for (auto [id, activation] : llvm::enumerate(activations))
    owners[activation] = id;
  for (auto [id, step] : llvm::enumerate(schedule.nodes)) {
    unsigned owner = owners.at(step.activation);
    ownerOf[id] = owner;
    position[id] = sequences[owner].size();
    sequences[owner].push_back(id);
  }
  // A virtual final step encounters the original event control again. Its
  // watched inputs must receive their last publication before that re-arm.
  // These steps are part of the scheduling proof, not executable operations
  // to clone: the fused body ends at the common suspension.
  std::vector<std::array<unsigned, 8>> required(nodes + count);
  for (auto dependency : schedule.dependencies)
    required[dependency.target][ownerOf[dependency.source]] =
        std::max(required[dependency.target][ownerOf[dependency.source]],
                 position[dependency.source] + 1);
  SmallVector<RangeSet> watches(count);
  for (unsigned owner = 0; owner < count; ++owner) {
    watches[owner].unite(*activations[owner]->getWatchedRanges());
    sequences[owner].push_back(nodes + owner);
  }
  for (auto [id, step] : llvm::enumerate(schedule.nodes)) {
    const auto &writes = step.activation->getMemory().getWrites();
    auto requirePublications =
        [&, id = id](ArrayRef<ActivationMemoryAnalysis::Range> ranges) {
          for (unsigned owner = 0; owner < count; ++owner)
            if (owner != ownerOf[id] &&
                !watches[owner].intersectWith(ranges).empty())
              required[nodes + owner][ownerOf[id]] = std::max(
                  required[nodes + owner][ownerOf[id]], position[id] + 1);
        };
    if (wholeBodies)
      requirePublications(step.activation->getMemory().getMayWrites());
    else
      step.activation->getNode(step.operation)->walk([&](Operation *op) {
        auto found = writes.find(op);
        if (found != writes.end())
          requirePublications(found->second);
      });
  }
  struct State {
    std::vector<unsigned> progress;
    unsigned parent, actor, segments;
  };
  std::vector<State> states{
      {std::vector<unsigned>(count, 0), UINT_MAX, UINT_MAX, 0}};
  std::map<std::vector<unsigned>, unsigned> visited{{states[0].progress, 0}};
  size_t work = 0;
  size_t budget =
      std::max(size_t{65536},
               (schedule.nodes.size() + schedule.dependencies.size()) * 128);
  unsigned complete = UINT_MAX;
  for (unsigned cursor = 0; cursor < states.size() && complete == UINT_MAX;
       ++cursor) {
    auto progress = states[cursor].progress;
    unsigned segments = states[cursor].segments;
    for (unsigned actor = 0; actor < count; ++actor) {
      auto next = progress;
      while (next[actor] < sequences[actor].size()) {
        unsigned node = sequences[actor][next[actor]];
        bool ready = true;
        for (unsigned owner = 0; owner < count; ++owner) {
          if (++work > budget)
            return std::nullopt;
          ready &= next[owner] >= required[node][owner];
        }
        if (!ready)
          break;
        ++next[actor];
      }
      if (next == progress || visited.find(next) != visited.end())
        continue;
      if (states.size() == 4096)
        return std::nullopt;
      unsigned id = states.size();
      visited.emplace(next, id);
      states.push_back({std::move(next), cursor, actor, segments + 1});
      bool done = true;
      for (unsigned owner = 0; owner < count; ++owner)
        done &= states.back().progress[owner] == sequences[owner].size();
      if (done) {
        complete = id;
        break;
      }
    }
  }
  if (complete == UINT_MAX)
    return std::nullopt;
  // Advancing a ready source prefix cannot disable another step. Therefore
  // an optimal order can always run each chosen actor until blocked. BFS of
  // precisely those maximal runs minimizes handoffs; an exhausted search is
  // unavailable, never an approximate optimum.
  handoffs = states[complete].segments - 1;
  SmallVector<unsigned> path;
  for (unsigned id = complete; id; id = states[id].parent)
    path.push_back(id);
  SmallVector<ActivationRegionStep> order;
  order.reserve(nodes);
  for (unsigned id : llvm::reverse(path)) {
    const State &state = states[id], &previous = states[state.parent];
    if (runs)
      runs->push_back(activations[state.actor]);
    if (held && previous.progress[state.actor])
      held->push_back(activations[state.actor]);
    if (preemptions &&
        state.progress[state.actor] < sequences[state.actor].size()) {
      unsigned next = sequences[state.actor][state.progress[state.actor]];
      preemptions->push_back(
          next < nodes
              ? schedule.nodes[next]
              : ActivationRegionStep{activations[state.actor], nullptr});
    }
    for (unsigned i = previous.progress[state.actor];
         i < state.progress[state.actor]; ++i) {
      unsigned node = sequences[state.actor][i];
      if (node < nodes)
        order.push_back(schedule.nodes[node]);
    }
  }
  return order;
}
} // namespace

SmallVector<SmallVector<const ActivationRegionAnalysis *>>
getActivationPulseComponents(
    ArrayRef<const ActivationRegionAnalysis *> activations) {
  using Range = ActivationMemoryAnalysis::Range;
  SmallVector<unsigned> owners;
  DenseMap<uint64_t, SmallVector<std::pair<unsigned, Range>>> watchers;
  for (auto [owner, activation] : llvm::enumerate(activations))
    if (activation->isValid() && activation->getWatchedRanges() &&
        activation->getActivationFunction().getEntryKind() ==
            sim::EntryKind::AlwaysComb &&
        !activation->getMemory().getRepeatedWrites().empty()) {
      owners.push_back(owner);
      for (Range range : *activation->getWatchedRanges())
        watchers[range.root].emplace_back(owner, range);
    }
  DenseMap<unsigned, SmallVector<unsigned>> edges;
  size_t work = 0, budget = std::max(size_t{65536}, owners.size() * 256);
  for (unsigned owner : owners) {
    for (Range write : activations[owner]->getMemory().getRepeatedWrites()) {
      auto found = watchers.find(write.root);
      if (found == watchers.end())
        continue;
      for (auto [reader, read] : found->second) {
        if (++work > budget)
          return {};
        if (reader != owner && write.low < read.low + read.width &&
            read.low < write.low + write.width)
          edges[owner].push_back(reader);
      }
    }
    auto &targets = edges[owner];
    llvm::sort(targets);
    targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
  }
  SmallVector<SmallVector<const ActivationRegionAnalysis *>> result;
  for (auto component :
       computeStronglyConnectedComponents<unsigned>(owners, edges)) {
    if (component.size() < 2)
      continue;
    llvm::sort(component);
    auto &cohort = result.emplace_back();
    for (unsigned owner : component)
      cohort.push_back(activations[owner]);
  }
  return result;
}

std::optional<ActivationRearmPlan>
getActivationRearmPlan(ArrayRef<const ActivationRegionAnalysis *> activations,
                       ActivationRearmPlan::Trace trace) {
  if (activations.size() > 8)
    return std::nullopt;
  ActivationRearmPlan result;
  if (!hasPossiblePulseCycle(activations, trace))
    return result;
  // Source execution does not require a read to see a later publication.
  // Such value edges belong to the separate settled-value fusion proof.
  // The only cross-process requirements here precede the original re-arms.
  ActivationSchedule bodies;
  for (const auto *activation : activations)
    bodies.nodes.push_back(
        {activation, activation->getActivationFunction().getOperation()});
  std::optional<unsigned> handoffs;
  auto order =
      minimumHandoffOrder(bodies, activations, handoffs, &result.preemptions,
                          /*wholeBodies=*/true, nullptr, &result.runs);
  if (!order)
    return std::nullopt;
  for (const auto &step : *order)
    result.bodyOrder.push_back(step.activation);
  result.minimumHandoffs = *handoffs;
  return result;
}

std::optional<ActivationSchedule> getActivationRegionSchedule(
    ArrayRef<const ActivationRegionAnalysis *> activations) {
  return buildActivationRegionSchedule(activations);
}

void ActivationInterleavingPreparation::prepare(
    ArrayRef<const ActivationRegionAnalysis *> activations) {
  if (prepared && llvm::equal(preparedActivations, activations))
    return;
  prepared = true;
  preparedActivations.assign(activations.begin(), activations.end());
  schedule.reset();
  if (!mayHavePulseCycle(activations))
    return;
  schedule = buildActivationRegionSchedule(activations, nullptr, true);
  if (!schedule || schedule->isAcyclic())
    return;
  for (const auto *activation : activations) {
    if (frontierViews.contains(activation) ||
        !llvm::any_of(activation->getNodes(), [](const auto &node) {
          return node.isRegion() && !node.reads.empty() && !node.writes.empty();
        }))
      continue;
    auto &refined = frontierViews[activation];
    if (auto view = prepareActivationFrontiers(*activation, handles)) {
      refined = std::make_unique<ActivationRegionAnalysis>(
          std::move(*view), handles, activation->getDependencyMode());
      if (!refined->isValid())
        refined.reset();
    }
  }
}

std::optional<SmallVector<ActivationRegionStep>>
ActivationInterleavingAnalysis::getOrder(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    SmallVectorImpl<ActivationRegionStep> *cycle) {
  assert(preparation.prepared &&
         llvm::equal(preparation.preparedActivations, activations) &&
         "prepare activation views before querying interleavings");
  if (!cached || !llvm::equal(cachedActivations, activations) ||
      (cycle && !cachedCycleAvailable)) {
    cachedCycle.clear();
    cachedOrder = computeOrder(activations, cycle ? &cachedCycle : nullptr);
    cachedActivations.assign(activations.begin(), activations.end());
    cached = true;
    cachedCycleAvailable = cycle != nullptr;
  }
  if (cycle)
    cycle->assign(cachedCycle.begin(), cachedCycle.end());
  return cachedOrder;
}

std::optional<SmallVector<ActivationRegionStep>>
ActivationInterleavingAnalysis::computeOrder(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    SmallVectorImpl<ActivationRegionStep> *cycle) {
  if (cycle)
    cycle->clear();
  minimumHandoffs.reset();
  preemptions.clear();
  runs.clear();
  provenLivelock = hasPossiblePulseCycle(activations);
  SmallVector<const ActivationRegionAnalysis *> selected(activations);
  bool pulseCandidates = mayHavePulseCycle(activations);
  if (!provenLivelock && !pulseCandidates)
    return getActivationRegionOrder(activations, cycle);
  auto schedule = preparation.schedule;
  if (pulseCandidates && schedule && !schedule->isAcyclic()) {
    bool changed = false;
    for (auto &activation : selected) {
      if (!llvm::any_of(activation->getNodes(), [](const auto &node) {
            return node.isRegion() && !node.reads.empty() &&
                   !node.writes.empty();
          }))
        continue;
      if (const auto *refined = preparation.getFrontierView(activation)) {
        activation = refined;
        changed = true;
      }
    }
    if (changed) {
      if (!provenLivelock)
        provenLivelock = hasPossiblePulseCycle(selected);
      if (provenLivelock)
        schedule = buildActivationRegionSchedule(selected, nullptr, true);
    }
  }
  if (!provenLivelock)
    return getActivationRegionOrder(activations, cycle);
  if (!schedule)
    return getActivationRegionOrder(activations, cycle);
  if (!schedule->isAcyclic()) {
    DenseSet<const ActivationRegionAnalysis *> cyclic;
    for (auto [node, step] : llvm::enumerate(schedule->nodes))
      if (schedule->cyclic[schedule->componentOf[node]])
        cyclic.insert(step.activation);
    for (const auto *activation : selected) {
      if (!cyclic.contains(activation) || demandedReads.contains(activation))
        continue;
      DemandedBitAnalysis demands(activation->getActivationFunction());
      auto &refined = demandedReads[activation];
      for (const auto &[operation, ranges] :
           activation->getMemory().getReads()) {
        auto load = dyn_cast<sim::SimRefLoadOp>(operation);
        const APInt *mask = load ? demands.get(load.getResult()) : nullptr;
        auto &reads = refined[operation];
        for (Range range : ranges) {
          if (!mask || mask->getBitWidth() != range.width ||
              mask->isAllOnes()) {
            reads.push_back(range);
            continue;
          }
          for (unsigned bit = 0; bit < mask->getBitWidth();) {
            if (!(*mask)[bit]) {
              ++bit;
              continue;
            }
            unsigned begin = bit++;
            while (bit < mask->getBitWidth() && (*mask)[bit])
              ++bit;
            reads.push_back({range.root, range.low + begin, bit - begin});
          }
        }
      }
    }
    schedule = buildActivationRegionSchedule(selected, &demandedReads, true);
    if (!schedule)
      return getActivationRegionOrder(activations, cycle);
  }
  if (!schedule->isAcyclic()) {
    if (cycle) {
      SmallVector<std::pair<unsigned, unsigned>> edges;
      for (auto dependency : schedule->dependencies)
        edges.emplace_back(dependency.source, dependency.target);
      orderSteps(schedule->nodes, std::move(edges), cycle);
    }
    return std::nullopt;
  }
  auto order = minimumHandoffOrder(*schedule, selected, minimumHandoffs,
                                   nullptr, false, &preemptions, &runs);
  return order ? order : getActivationRegionOrder(activations, cycle);
}

std::optional<SmallVector<ActivationRegionStep>>
getActivationRegionOrder(ArrayRef<const ActivationRegionAnalysis *> activations,
                         SmallVectorImpl<ActivationRegionStep> *cycle) {
  if (cycle)
    cycle->clear();
  auto schedule = getActivationRegionSchedule(activations);
  if (!schedule)
    return std::nullopt;
  SmallVector<std::pair<unsigned, unsigned>> edges;
  for (auto dependency : schedule->dependencies)
    edges.emplace_back(dependency.source, dependency.target);
  return orderSteps(schedule->nodes, std::move(edges), cycle);
}

namespace {
bool isSliceablePackedScalar(Type type) {
  if (isa_and_nonnull<sim::LogicType>(type))
    return true;
  auto integer = dyn_cast_or_null<IntegerType>(type);
  return integer && integer.isSignless();
}

std::optional<ActivationSchedule>
buildSliceSchedule(ArrayRef<const ActivationRegionAnalysis *> activations,
                   SmallVectorImpl<ActivationRegionStep> *cycle,
                   const ActivationSliceOptions &options) {
  if (cycle)
    cycle->clear();
  if (options.cyclic)
    options.cyclic->clear();
  struct StoreNode {
    const ActivationRegionAnalysis *activation;
    SmallVector<Operation *> stores;
    /// Dependence inputs. Initially the physical ranges of the loads the
    /// stores depend on; a node on a cycle is refined to the simplified
    /// slice's loads intersected with its lane publication inputs, which are
    /// exact through extracts and copies.
    Ranges reads, writes;
    /// Physical load ranges following reconstructed temporaries. They decide
    /// which source-local stores must share one slice (IEEE 1800-2023 4.6).
    Ranges localReads;
    /// Lane publication inputs of the stores, when the activation has them.
    Ranges laneReads;
    /// A lane-copy store kept only over this root-relative window.
    std::optional<Range> window;
    /// Corresponding source lanes of a whole publication; on a cycle the
    /// node is split at lanes other nodes read or write. Emission retains the
    /// original computation, without assuming source and result values equal.
    std::optional<Range> identity;
  };
  auto overlaps = [](ArrayRef<Range> a, ArrayRef<Range> b) {
    for (const auto &x : a)
      for (const auto &y : b)
        if (x.root == y.root && x.low < y.low + y.width &&
            y.low < x.low + x.width)
          return true;
    return false;
  };
  SmallVector<StoreNode, 0> nodes;
  for (const auto *activation : activations) {
    if (!activation->isValid())
      return std::nullopt;
    const auto &memory = activation->getMemory();
    // IEEE 1800-2023 4.6 preserves source-local store/load ordering. A store
    // selecting between a private slot and canonical storage participates in
    // both dependency graphs. Until slicing models that coupling, retain the
    // whole activation instead of dropping the private update in another slice.
    if (memory.hasMixedPrivateWrites())
      return std::nullopt;
    bool lanes = memory.hasValueDependencies();
    // IEEE 1800-2023 4.6(a)/10.4.1: a retained-state update must precede
    // later source publications that can feed back and disable that update.
    // Fixed-input idempotence alone does not permit separating those effects:
    // `if (enable) q = d; request = a` must capture before request changes
    // enable through another process. Keep the complete activation together,
    // including explicit self-assignment and implicit per-cell holds. Derive
    // this from the current IR, independently of caller-supplied atomicity.
    bool retains =
        !memory.hasCompleteWrites() ||
        overlaps(lanes ? memory.getFinalInputs() : memory.getLiveIns(),
                 memory.getMayWrites());
    bool atomic =
        retains || (options.atomic && options.atomic->contains(activation));
    ActivationLoadSlice slice(activation->getActivationFunction(), memory);
    auto temporaries = getActivationTemporaryRoots(
        activation->getActivationFunction(), memory);
    DenseMap<uint64_t, SmallVector<Operation *>> temporaryWriters;
    for (auto [base, root] : temporaries)
      temporaryWriters.try_emplace(root);
    DenseMap<Operation *, Ranges> sourceReads;
    activation->getActivationFunction().walk([&](Operation *store) {
      auto writes = memory.getWrites().find(store);
      if (writes == memory.getWrites().end())
        return;
      SmallVector<Operation *> loads;
      slice.collect(store, loads);
      for (Operation *load : loads)
        if (auto reads = memory.getReads().find(load);
            reads != memory.getReads().end())
          unionRanges(sourceReads[store], reads->second);
      for (auto range : writes->second)
        if (auto found = temporaryWriters.find(range.root);
            found != temporaryWriters.end())
          found->second.push_back(store);
    });
    SmallVector<StoreNode, 0> local;
    activation->getActivationFunction().walk([&](Operation *store) {
      auto writes = memory.getWrites().find(store);
      if (writes == memory.getWrites().end())
        return;
      StoreNode node{activation, {store}, {}, writes->second, {}, {}, {}, {}};
      // Follow reconstructed temporary definitions in the immutable summary.
      // Only cycle witnesses need executable clones and CFG simplification;
      // cloning every publication would make planning quadratic in body size.
      SmallVector<Operation *> pending{store};
      DenseSet<Operation *> seen{store};
      while (!pending.empty()) {
        Operation *definition = pending.pop_back_val();
        for (auto read : sourceReads.lookup(definition)) {
          auto temporary = temporaryWriters.find(read.root);
          if (temporary == temporaryWriters.end()) {
            unionRanges(node.localReads, {read});
            continue;
          }
          for (Operation *writer : temporary->second)
            if (overlaps({read}, memory.getWrites().lookup(writer)) &&
                seen.insert(writer).second)
              pending.push_back(writer);
        }
      }
      node.reads = node.localReads;
      if (lanes) {
        const auto &publications = memory.getPublications().lookup(store);
        for (const auto &publication : publications)
          unionRanges(node.laneReads, publication.inputs);
        if (auto refStore = dyn_cast<sim::SimRefStoreOp>(store);
            !atomic && refStore && publications.size() == 1 &&
            publications.front().identity && writes->second.size() == 1 &&
            publications.front().output == writes->second.front() &&
            isSliceablePackedScalar(sim::getPackedScalarType(
                refStore.getReference().getType().getElementType())))
          node.identity = publications.front().identity;
      }
      // Keep all remaining source-local memory dependence in one slice.
      // Reconstructed private versions have no canonical read dependency;
      // all other snapshots still need their source stores in the same slice.
      // Restart after merging, since a newly included range can connect a
      // previously disjoint group. An atomic activation keeps every store in
      // one slice, in source order.
      for (bool changed = true; changed;) {
        changed = false;
        for (auto it = local.begin(); it != local.end();) {
          if (!atomic && !overlaps(it->writes, node.writes) &&
              !overlaps(it->writes, node.localReads) &&
              !overlaps(it->localReads, node.writes)) {
            ++it;
            continue;
          }
          llvm::append_range(node.stores, it->stores);
          unionRanges(node.reads, it->reads);
          unionRanges(node.localReads, it->localReads);
          unionRanges(node.laneReads, it->laneReads);
          unionRanges(node.writes, it->writes);
          node.identity.reset();
          it = local.erase(it);
          changed = true;
        }
      }
      local.push_back(std::move(node));
    });
    for (auto &node : local)
      nodes.push_back(std::move(node));
  }
  // Split a lane-copy node where other nodes read its destination or write
  // its source, so a reader of some lanes no longer waits for the writer of
  // other lanes (and the reverse). Each part is a partial store of the same
  // operation; emission narrows it to the window. Empty when nothing cuts.
  constexpr size_t maximumParts = 64;
  auto splitLaneCopy = [&](size_t index) {
    SmallVector<StoreNode, 0> parts;
    const StoreNode &node = nodes[index];
    Range output = node.writes.front();
    Range source = *node.identity;
    uint64_t end = output.low + output.width;
    SmallVector<uint64_t> cuts{output.low, end};
    auto cut = [&](uint64_t low, uint64_t high) {
      if (low > output.low && low < end)
        cuts.push_back(low);
      if (high > output.low && high < end)
        cuts.push_back(high);
    };
    for (size_t other = 0; other < nodes.size(); ++other) {
      if (other == index)
        continue;
      for (const auto &read : nodes[other].reads)
        if (read.root == output.root)
          cut(read.low, read.low + read.width);
      for (const auto &write : nodes[other].writes)
        if (write.root == source.root && write.low + write.width > source.low &&
            write.low < source.low + source.width) {
          uint64_t low = std::max(write.low, source.low) - source.low;
          uint64_t high =
              std::min(write.low + write.width, source.low + source.width) -
              source.low;
          cut(output.low + low, output.low + high);
        }
    }
    llvm::sort(cuts);
    cuts.erase(std::unique(cuts.begin(), cuts.end()), cuts.end());
    if (cuts.size() <= 2 || cuts.size() - 1 > maximumParts)
      return parts;
    for (size_t i = 1; i < cuts.size(); ++i) {
      StoreNode part = node;
      part.identity.reset();
      part.window = Range{output.root, cuts[i - 1], cuts[i] - cuts[i - 1]};
      part.writes = {*part.window};
      part.reads = {Range{source.root, source.low + (cuts[i - 1] - output.low),
                          cuts[i] - cuts[i - 1]}};
      part.laneReads = part.reads;
      parts.push_back(std::move(part));
    }
    return parts;
  };
  SmallVector<ActivationRegionStep> steps;
  SmallVector<std::pair<unsigned, unsigned>> edges;
  DenseMap<uint64_t, SmallVector<unsigned>> readers;
  auto rebuild = [&] {
    steps.clear();
    for (const auto &node : nodes)
      steps.push_back({node.activation, node.stores.front()});
    edges.clear();
    readers.clear();
    for (auto [id, node] : llvm::enumerate(nodes))
      for (const auto &read : node.reads)
        readers[read.root].push_back(id);
    for (auto [id, node] : llvm::enumerate(nodes))
      for (const auto &write : node.writes)
        for (unsigned reader : readers.lookup(write.root))
          if (reader != id && overlaps({write}, nodes[reader].reads))
            edges.emplace_back(id, reader);
  };
  rebuild();
  DenseSet<std::pair<const ActivationRegionAnalysis *, Operation *>> refined;
  while (true) {
    SmallVector<ActivationRegionStep> witness;
    if (orderSteps(steps, edges, &witness))
      break;
    SmallVector<unsigned> ids(nodes.size());
    std::iota(ids.begin(), ids.end(), 0u);
    DenseMap<unsigned, SmallVector<unsigned>> adjacency;
    for (auto [from, to] : edges)
      adjacency[from].push_back(to);
    auto components =
        computeStronglyConnectedComponents<unsigned>(ids, adjacency);
    SmallVector<bool> cyclicNodes(nodes.size(), false);
    for (const auto &component : components)
      if (component.size() > 1)
        for (unsigned id : component)
          cyclicNodes[id] = true;
    // Refine every cyclic component: an irreducible witness in one component
    // must not prevent precision from breaking a false cycle elsewhere, or
    // elsewhere in the same component. Only cyclic nodes pay for precision:
    // a lane copy is split into its windows; other physical reads are replaced
    // by the simplified slice's loads intersected with its exact lane inputs.
    // This removes loads in control paths that only other stores need.
    bool changed = false;
    auto refineNode = [&](size_t index) {
      StoreNode &node = nodes[index];
      if (!refined.insert({node.activation, node.stores.front()}).second)
        return false;
      auto reads = getSliceReads({node.activation, node.stores, {}});
      if (!reads)
        return false;
      Ranges precise = node.laneReads.empty()
                           ? std::move(*reads)
                           : intersectRanges(*reads, node.laneReads);
      if (precise == node.reads)
        return false;
      node.reads = std::move(precise);
      return true;
    };
    SmallVector<size_t> splits, refinements;
    for (auto [index, node] : llvm::enumerate(nodes)) {
      if (!cyclicNodes[index] || node.window)
        continue;
      (node.identity ? splits : refinements).push_back(index);
    }
    for (size_t index : refinements)
      changed |= refineNode(index);
    // Descending, so earlier indices stay valid while parts are inserted.
    llvm::sort(splits, std::greater<size_t>());
    for (size_t index : splits) {
      SmallVector<StoreNode, 0> parts = splitLaneCopy(index);
      nodes[index].identity.reset();
      if (parts.empty()) {
        changed |= refineNode(index);
        continue;
      }
      nodes.erase(nodes.begin() + index);
      nodes.insert(nodes.begin() + index,
                   std::make_move_iterator(parts.begin()),
                   std::make_move_iterator(parts.end()));
      changed = true;
    }
    if (!changed) {
      if (cycle)
        llvm::append_range(*cycle, witness);
      if (options.cyclic) {
        llvm::SmallSetVector<const ActivationRegionAnalysis *, 8> cyclic;
        for (const auto &component : components)
          if (component.size() > 1)
            for (unsigned id : component)
              cyclic.insert(nodes[id].activation);
        llvm::append_range(*options.cyclic, cyclic);
      }
      break;
    }
    // Rebuild only dependencies. Store grouping protects source-local
    // snapshots and is never weakened by control-flow simplification.
    rebuild();
  }
  ActivationSchedule result;
  result.nodes = steps;
  for (const auto *activation : activations)
    result.sensitivityEvents.push_back(activation->getSuspension());
  for (auto [from, to] : edges)
    result.dependencies.push_back(
        {from, to, ActivationSchedule::DependencyKind::Value});
  for (const auto &node : nodes) {
    ActivationSlice slice{node.activation, node.stores, {}};
    if (node.window)
      slice.windows.emplace_back(node.stores.front(), *node.window);
    result.slices.push_back(std::move(slice));
  }
  if (!buildComponents(result))
    return std::nullopt;
  if (!result.isAcyclic())
    return result;
  // Topological order that continues with the previous activation whenever
  // possible, so each process is split into as few slices as possible.
  llvm::sort(edges);
  edges.erase(std::unique(edges.begin(), edges.end()), edges.end());
  SmallVector<SmallVector<unsigned>> successors(nodes.size());
  SmallVector<unsigned> incoming(nodes.size(), 0);
  for (auto [from, to] : edges) {
    successors[from].push_back(to);
    ++incoming[to];
  }
  // Among ready nodes, prefer a newly unblocked consumer. This shortens
  // live ranges when loads from its producers are forwarded into SSA.
  // Keep one stack per activation for the same-process preference. A node
  // taken from either stack is discarded lazily from the other.
  SmallVector<unsigned> ready;
  DenseMap<const ActivationRegionAnalysis *, SmallVector<unsigned, 4>> byOwner;
  SmallVector<bool> scheduled(nodes.size(), false);
  auto enqueue = [&](unsigned id) {
    ready.push_back(id);
    byOwner[nodes[id].activation].push_back(id);
  };
  auto discardScheduled = [&](auto &stack) {
    while (!stack.empty() && scheduled[stack.back()])
      stack.pop_back();
  };
  // Reverse insertion preserves source order among simultaneous releases.
  for (unsigned id = nodes.size(); id != 0; --id)
    if (!incoming[id - 1])
      enqueue(id - 1);
  result.order.clear();
  const ActivationRegionAnalysis *previous = nullptr;
  while (result.order.size() < nodes.size()) {
    discardScheduled(ready);
    unsigned id = ready.back();
    if (previous) {
      auto &same = byOwner.at(previous);
      discardScheduled(same);
      if (!same.empty())
        id = same.back();
    }
    scheduled[id] = true;
    result.order.push_back(id);
    previous = nodes[id].activation;
    for (unsigned successor : llvm::reverse(successors[id]))
      if (!--incoming[successor])
        enqueue(successor);
  }
  // Rebuild component identities for the chosen DAG order. Every component
  // is a singleton; identities must agree with offsets into this order.
  for (auto [rank, id] : llvm::enumerate(result.order))
    result.componentOf[id] = rank;
  return result;
}
} // namespace

std::optional<ActivationSchedule> getActivationSliceSchedule(
    ArrayRef<const ActivationRegionAnalysis *> activations,
    const ActivationSliceOptions &options) {
  return buildSliceSchedule(activations, nullptr, options);
}

std::optional<SmallVector<ActivationSlice>>
getActivationSliceOrder(ArrayRef<const ActivationRegionAnalysis *> activations,
                        SmallVectorImpl<ActivationRegionStep> *cycle,
                        const ActivationSliceOptions &options) {
  auto schedule = buildSliceSchedule(activations, cycle, options);
  if (!schedule || !schedule->isAcyclic())
    return std::nullopt;
  SmallVector<ActivationSlice> slices;
  for (unsigned id : schedule->order) {
    const auto &node = schedule->slices[id];
    if (slices.empty() || slices.back().activation != node.activation)
      slices.push_back({node.activation, {}, {}});
    for (Operation *store : node.stores)
      if (!llvm::is_contained(slices.back().stores, store))
        slices.back().stores.push_back(store);
    llvm::append_range(slices.back().windows, node.windows);
  }
  return slices;
}

namespace {
OwningOpRef<sim::SimFuncOp>
cloneSliceWithTemporaries(const ActivationSlice &slice,
                          IRMapping &mappingStorage,
                          const DenseMap<Value, uint64_t> &temporaries) {
  IRMapping *mapping = &mappingStorage;
  auto function = slice.activation->getActivationFunction();
  const auto &memory = slice.activation->getMemory();
  OwningOpRef<sim::SimFuncOp> copy(
      cast<sim::SimFuncOp>(function->clone(*mapping)));
  DenseMap<Value, Value> privateReferences;
  DenseMap<uint64_t, Value> slots;
  OpBuilder entry(&copy->getBody().front(), copy->getBody().front().begin());
  // Iterate source order, never DenseMap order: stable slot order matters to
  // deterministic planning and generated IR.
  auto allocate = [&](Value base) {
    auto found = temporaries.find(base);
    if (found == temporaries.end())
      return;
    auto ref = cast<sim::RefType>(base.getType());
    Value &slot = slots[found->second];
    if (!slot) {
      Type type = ref.getElementType();
      Value initial;
      if (sim::isAggregateType(type))
        initial =
            sim::SimAggregateDefaultOp::create(entry, base.getLoc(), type);
      else if (isa<IntegerType>(type))
        initial = arith::ConstantOp::create(entry, base.getLoc(), type,
                                            entry.getIntegerAttr(type, 0));
      else {
        auto logic = cast<sim::LogicType>(type);
        auto plane = entry.getIntegerType(logic.getWidth());
        initial = sim::SimLogicConstantOp::create(
            entry, base.getLoc(), type,
            entry.getIntegerAttr(plane, APInt(logic.getWidth(), 0)),
            entry.getIntegerAttr(plane, APInt::getAllOnes(logic.getWidth())));
      }
      slot = sim::SimRefAllocOp::create(entry, base.getLoc(), ref, initial);
    }
    privateReferences[base] = slot;
  };
  for (BlockArgument argument : function.getArguments())
    allocate(argument);
  function.walk(
      [&](sim::SimContextStorageOp storage) { allocate(storage.getResult()); });
  auto privateReference = [&](Value reference,
                              auto &privateReference) -> Value {
    if (Value found = privateReferences.lookup(reference))
      return found;
    Operation *definition = reference.getDefiningOp();
    assert(definition && "temporary reference was validated");
    IRMapping operands;
    for (Value operand : definition->getOperands())
      operands.map(operand, isa<sim::RefType>(operand.getType())
                                ? privateReference(operand, privateReference)
                                : mapping->lookup(operand));
    OpBuilder builder(mapping->lookup(definition));
    Operation *cloned = builder.clone(*definition, operands);
    for (auto [from, to] :
         llvm::zip_equal(definition->getResults(), cloned->getResults()))
      privateReferences[from] = to;
    return privateReferences.lookup(reference);
  };
  DenseSet<Operation *> kept;
  for (Operation *store : slice.stores)
    kept.insert(mapping->lookup(store));
  DenseMap<Operation *, Ranges> reads, writes;
  DenseSet<Operation *> privateReads;
  for (Operation *read : memory.getPrivateReads())
    privateReads.insert(mapping->lookup(read));
  for (const auto &[op, ranges] : memory.getReads()) {
    auto load = dyn_cast<sim::SimRefLoadOp>(op);
    if (load && !ranges.empty() && slots.contains(ranges.front().root)) {
      cast<sim::SimRefLoadOp>(mapping->lookup(op))
          .getReferenceMutable()
          .assign(privateReference(load.getReference(), privateReference));
    } else
      reads[mapping->lookup(op)] = ranges;
  }
  function.walk([&](Operation *op) {
    auto found = memory.getWrites().find(op);
    if (found == memory.getWrites().end())
      return;
    Operation *cloned = mapping->lookup(op);
    if (auto store = dyn_cast<sim::SimRefStoreOp>(op);
        store && !found->second.empty() &&
        slots.contains(found->second.front().root)) {
      OpBuilder builder(cloned);
      sim::SimRefStoreOp::create(
          builder, store.getLoc(), mapping->lookup(store.getValue()),
          privateReference(store.getReference(), privateReference));
    }
    if (kept.contains(cloned))
      writes[cloned] = found->second;
    else
      cloned->erase();
  });
  // A lane-copy store listed with windows publishes only those lanes here:
  // narrow it to one partial store per window. The whole value is still
  // computed from the same loads; other windows belong to other slices.
  for (size_t index = 0; index < slice.windows.size(); ++index) {
    Operation *store = slice.windows[index].first;
    if (llvm::any_of(ArrayRef(slice.windows).take_front(index),
                     [&](const auto &entry) { return entry.first == store; }))
      continue;
    auto cloned = cast<sim::SimRefStoreOp>(mapping->lookup(store));
    auto found = writes.find(cloned);
    if (found == writes.end() || found->second.size() != 1)
      return {};
    Range whole = found->second.front();
    OpBuilder builder(cloned);
    Location loc = cloned.getLoc();
    Value value = cloned.getValue();
    Type scalar = sim::getPackedScalarType(value.getType());
    if (!isSliceablePackedScalar(scalar))
      return {};
    if (value.getType() != scalar)
      value = sim::SimPackedFlattenOp::create(builder, loc, scalar, value);
    for (const auto &[other, window] : slice.windows) {
      if (other != store)
        continue;
      if (window.low < whole.low ||
          window.low + window.width > whole.low + whole.width)
        return {};
      uint64_t low = window.low - whole.low;
      Type partType;
      Value part;
      if (isa<sim::LogicType>(scalar)) {
        partType = sim::LogicType::get(builder.getContext(), window.width);
        part =
            sim::SimLogicExtractOp::create(builder, loc, partType, value, low);
      } else {
        partType = builder.getIntegerType(window.width);
        part = value;
        if (low) {
          Value offset = arith::ConstantOp::create(
              builder, loc, builder.getIntegerAttr(scalar, low));
          part = arith::ShRUIOp::create(builder, loc, part, offset);
        }
        if (partType != scalar)
          part = arith::TruncIOp::create(builder, loc, partType, part);
      }
      Value reference = sim::SimRefExtractOp::create(
          builder, loc, sim::RefType::get(builder.getContext(), partType),
          cloned.getReference(), low);
      auto narrowed = sim::SimRefStoreOp::create(builder, loc, part, reference);
      if (auto owner = schedule::get<schedule::Field::EvalSourceOwner>(cloned))
        schedule::set<schedule::Field::EvalSourceOwner>(narrowed, owner);
      if (schedule::has<schedule::Field::EvalNbaEquivalentStore>(cloned))
        schedule::set<schedule::Field::EvalNbaEquivalentStore>(
            narrowed, builder.getUnitAttr());
      writes[narrowed] = {window};
    }
    writes.erase(cloned);
    cloned->erase();
  }
  auto removeDeadStores = [&] {
    ActivationLoadSlice dependencies(*copy, reads, writes, &privateReads);
    DenseSet<Operation *> required;
    SmallVector<Operation *> loads;
    copy->walk([&](Operation *op) {
      if (isa<sim::SimRefStoreOp, sim::SimDriverDriveOp>(op) &&
          writes.contains(op))
        dependencies.collect(op, loads, &required);
    });
    SmallVector<Operation *> deadStores;
    copy->walk([&](sim::SimRefStoreOp store) {
      if (!writes.contains(store) && !required.contains(store))
        deadStores.push_back(store);
    });
    for (Operation *store : deadStores)
      store->erase();
    return !deadStores.empty();
  };
  removeDeadStores();
  if (failed(canonicalizeActivationControlFlow(*copy)))
    return {};
  while (true) {
    // Removing a branch can make a private load dead; its reaching stores
    // must then be sliced again before their own inputs can disappear.
    bool removedStores = removeDeadStores();
    // Admission proved every call finite and read-only. Its generic call
    // interface remains conservative, so ordinary DCE cannot remove it when
    // slicing discards all results. Retaining it would retain its input reads
    // and could keep an otherwise empty loop alive.
    SmallVector<sim::SimCallOp> deadCalls;
    copy->walk([&](sim::SimCallOp call) {
      if (call->use_empty())
        deadCalls.push_back(call);
    });
    for (auto call : deadCalls)
      call.erase();
    bool removedLoop = removeEmptyFiniteLoop(*copy);
    if (deadCalls.empty() && !removedLoop && !removedStores)
      break;
    if (failed(canonicalizeActivationControlFlow(*copy)))
      return {};
  }
  return copy;
}
} // namespace

OwningOpRef<sim::SimFuncOp> cloneActivationSlice(const ActivationSlice &slice,
                                                 IRMapping *mapping) {
  if (slice.activation->getMemory().hasMixedPrivateWrites())
    return {};
  IRMapping localMapping;
  auto temporaries = getActivationTemporaryRoots(
      slice.activation->getActivationFunction(), slice.activation->getMemory());
  return cloneSliceWithTemporaries(slice, mapping ? *mapping : localMapping,
                                   temporaries);
}
} // namespace talos::analysis
