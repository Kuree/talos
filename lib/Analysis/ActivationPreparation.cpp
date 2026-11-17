//===- ActivationPreparation.cpp - Normalize activation proof views
//--------===//
#include "talos/Analysis/ActivationPreparation.h"
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/LivenessAnalysis.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/RegionGraphTraits.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Analysis/ActivationControlFlow.h"
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "talos/Analysis/BoundedLoopAnalysis.h"
#include "talos/Analysis/GraphAlgorithms.h"
#include "talos/Analysis/SSAValueAnalysis.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/ScopeExit.h"

using namespace mlir;
namespace talos::analysis {
namespace {
/// An activation creates each flushed private slot from its root and may then
/// execute the slot's resumption refresh, a store of the same root load into
/// the fresh slot. Without an intervening access of the root or the slot that
/// store rewrites the initial contents; drop it so the initial and resumed
/// views match.
void dropRedundantSlotRefreshes(sim::SimFuncOp function) {
  Block &entry = function.getBody().front();
  SmallVector<Operation *> redundant;
  for (Operation &op : entry) {
    auto alloc = dyn_cast<sim::SimRefAllocOp>(op);
    if (!alloc || !sim::has<sim::metadata::FlushedPrivateSlot>(alloc))
      continue;
    auto initial = alloc.getInitialValue().getDefiningOp<sim::SimRefLoadOp>();
    Value root = initial ? initial.getReference() : Value{};
    for (Operation *next = alloc->getNextNode(); next;
         next = next->getNextNode()) {
      auto store = dyn_cast<sim::SimRefStoreOp>(next);
      auto load = store ? store.getValue().getDefiningOp<sim::SimRefLoadOp>()
                        : sim::SimRefLoadOp{};
      if (store && store.getReference() == alloc.getResult() &&
          (store.getValue() == alloc.getInitialValue() ||
           (root && load && load.getReference() == root))) {
        redundant.push_back(store);
        break;
      }
      // Pure computations, loads, fresh slots and stores into other fresh
      // slots touch neither this slot nor its root.
      auto otherSlot = [&](Value reference) {
        auto slot = reference.getDefiningOp<sim::SimRefAllocOp>();
        return slot && slot != alloc;
      };
      if (!isMemoryEffectFree(next) &&
          !isa<sim::SimRefLoadOp, sim::SimRefAllocOp>(next) &&
          !(store && otherSlot(store.getReference())))
        break;
    }
  }
  for (Operation *store : redundant) {
    auto load = cast<sim::SimRefStoreOp>(store).getValue().getDefiningOp();
    store->erase();
    if (load && load->use_empty())
      load->erase();
  }
  // Place every slot, with its root load, immediately before its first use in
  // the entry block, so slot creation order does not distinguish the views.
  // Nothing in between writes the exclusive root or the fresh slot.
  SmallVector<sim::SimRefAllocOp> slots;
  for (Operation &op : entry)
    if (auto alloc = dyn_cast<sim::SimRefAllocOp>(op);
        alloc && sim::has<sim::metadata::FlushedPrivateSlot>(alloc))
      slots.push_back(alloc);
  for (auto alloc : slots) {
    auto initial = alloc.getInitialValue().getDefiningOp<sim::SimRefLoadOp>();
    Operation *first = entry.getTerminator();
    for (Operation *user : alloc->getUsers())
      if (Operation *ancestor = entry.findAncestorOpInBlock(*user);
          ancestor && ancestor->isBeforeInBlock(first))
        first = ancestor;
    if (sim::has<sim::metadata::ActivationDefaultSlot>(alloc)) {
      // Fresh default scratch does not read canonical state. Sinking its
      // allocation past unrelated pure initializers gives both views the
      // same placement even when several slots share an aggregate default.
      alloc->moveBefore(first);
      continue;
    }
    if (!initial || initial->getBlock() != &entry || !initial->hasOneUse())
      continue;
    bool clear = true;
    for (Operation *op = alloc->getNextNode(); op && op != first && clear;
         op = op->getNextNode())
      if (auto store = dyn_cast<sim::SimRefStoreOp>(op))
        clear = store.getReference() != initial.getReference();
      else
        clear = isMemoryEffectFree(op) ||
                isa<sim::SimRefLoadOp, sim::SimRefAllocOp>(op);
    if (!clear)
      continue;
    initial->moveBefore(first);
    alloc->moveBefore(first);
  }
}

OwningOpRef<sim::SimFuncOp>
cloneActivation(sim::SimFuncOp source, Operation *suspend, bool resume,
                IRMapping &mapping, ActivationPreparationOptions::Trace trace,
                ActivationPreparationOptions::ControlFlow control,
                const ControlActivationAnalysis *controlActivations) {
  auto copy = cast<sim::SimFuncOp>(source->clone(mapping));
  OwningOpRef<sim::SimFuncOp> owner(copy);
  DenseSet<Operation *> initialEffects;
  if (resume)
    for (Operation &op : source.getBody().front().without_terminator())
      if (!isMemoryEffectFree(&op))
        initialEffects.insert(mapping.lookup(&op));
  if (controlActivations)
    for (Operation *original :
         controlActivations->getUnobservableEnters(source)) {
      auto enter = cast<sim::SimControlEnterOp>(mapping.lookup(original));
      for (Operation *leave : llvm::make_early_inc_range(enter->getUsers())) {
        initialEffects.erase(leave);
        leave->erase();
      }
      initialEffects.erase(enter);
      enter.erase();
    }
  auto *wait = mapping.lookup(suspend);
  OpBuilder builder(wait);
  sim::SimReturnOp::create(builder, wait->getLoc(), ValueRange{});
  wait->erase();
  // The threading marker expresses where a constant was materialized, not
  // its value. It must not distinguish initial and resume computations.
  copy.walk(
      [](Operation *op) { sim::remove<sim::metadata::Rematerialized>(op); });
  if (resume) {
    auto *entryTerminator = copy.getBody().front().getTerminator();
    if (!isa<cf::BranchOp>(entryTerminator))
      return {};
    builder.setInsertionPoint(entryTerminator);
    SemanticValueRootAnalysis roots(source);
    DenseMap<Value, Value> rematerialized;
    DenseSet<Value> visiting;
    auto materialize = [&](Value value, auto &materialize) -> Value {
      value = roots.lookup(value);
      if (auto argument = dyn_cast<BlockArgument>(value))
        return argument.getOwner() == &source.getBody().front()
                   ? mapping.lookup(argument)
                   : Value{};
      if (Value found = rematerialized.lookup(value))
        return found;
      auto *definition = value.getDefiningOp();
      // A flushed private slot equals a fresh copy of its exclusive root at
      // every resumption: recreate it together with the root load.
      auto flushed = [](Operation *op) {
        return op && sim::has<sim::metadata::FlushedPrivateSlot>(op);
      };
      bool slotInitializer = isa_and_nonnull<sim::SimRefLoadOp>(definition) &&
                             definition->hasOneUse() &&
                             flushed(*definition->getUsers().begin());
      if (!definition || !visiting.insert(value).second ||
          definition->getNumRegions() ||
          (!flushed(definition) && !slotInitializer &&
           (!isMemoryEffectFree(definition) || !isSpeculatable(definition))))
        return {};
      IRMapping operands;
      for (Value operand : definition->getOperands()) {
        Value mapped = materialize(operand, materialize);
        if (!mapped)
          return {};
        operands.map(operand, mapped);
      }
      // Immutable entry definitions already dominate the new resume edge.
      // Reuse them when their operands are unchanged, retaining canonical
      // definition order (including aggregate defaults shared by slots).
      // A snapshot load is never reused by this rule.
      bool reuse = definition->getBlock() == &source.getBody().front() &&
                   isMemoryEffectFree(definition) &&
                   isSpeculatable(definition) &&
                   llvm::all_of(definition->getOperands(), [&](Value operand) {
                     return operands.lookup(operand) == mapping.lookup(operand);
                   });
      auto *cloned = reuse ? mapping.lookup(definition)
                           : builder.clone(*definition, operands);
      sim::remove<sim::metadata::Rematerialized>(cloned);
      for (auto [from, to] :
           llvm::zip_equal(definition->getResults(), cloned->getResults()))
        rematerialized[from] = to;
      visiting.erase(value);
      return rematerialized.lookup(value);
    };
    // Recreate flushed private slots in entry order so both activations
    // allocate them identically.
    for (Operation &op : source.getBody().front().without_terminator())
      if (sim::has<sim::metadata::FlushedPrivateSlot>(&op) &&
          !materialize(op.getResult(0), materialize))
        return {};
    auto branch = cast<BranchOpInterface>(suspend);
    SmallVector<Value> arguments;
    for (Value argument :
         branch.getSuccessorOperands(0).getForwardedOperands()) {
      Value mapped = materialize(argument, materialize);
      if (!mapped)
        return {};
      arguments.push_back(mapped);
    }
    // Unthreaded CFGs may use an entry slot directly instead of passing its
    // reference on the suspension edge. Rebind those uses to the recreated
    // slot too; otherwise the clone keeps an artificial bootstrap live-in.
    for (auto [original, recreated] : rematerialized)
      if (auto alloc = original.getDefiningOp<sim::SimRefAllocOp>();
          alloc && sim::has<sim::metadata::FlushedPrivateSlot>(alloc))
        mapping.lookup(original).replaceAllUsesWith(recreated);
    cf::BranchOp::create(builder, source.getLoc(),
                         mapping.lookup(suspend->getSuccessor(0)), arguments);
    entryTerminator->erase();
  }
  IRRewriter rewriter(copy.getContext());
  (void)eraseUnreachableBlocks(rewriter, copy.getBody());
  // Suspension threading can introduce forwarding cycles through loop
  // headers. Collapse their proven SSA identities before structuring, so a
  // stable reference does not become a loop-carried region result.
  propagateActivationValueRoots(copy);
  if (!initialEffects.empty()) {
    // A live one-time snapshot is captured state, not a fresh resume read.
    // Sparse backward liveness follows CFG forwarding lanes, including dead
    // phi cycles, before any rewrite can merge loads or recycle op addresses.
    SymbolTableCollection symbols;
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
    solver.load<dataflow::DeadCodeAnalysis>();
    solver.load<dataflow::SparseConstantPropagation>();
    solver.load<dataflow::LivenessAnalysis>(symbols);
    if (failed(solver.initializeAndRun(copy)))
      return {};
    for (Operation *effect : initialEffects) {
      if (!wouldOpBeTriviallyDead(effect))
        return {};
      for (Value result : effect->getResults()) {
        auto *state = solver.lookupState<dataflow::Liveness>(result);
        if (!state || state->isLive)
          return {};
      }
    }
  }
  if (failed(canonicalizeActivationControlFlow(copy)))
    return {};
  dropRedundantSlotRefreshes(copy);
  // Normalize lowered break/continue dispatch only when it obstructs the
  // ordinary induction proof. Already admitted activations keep their CFG.
  if (control == ActivationPreparationOptions::ControlFlow::ThreadDispatch &&
      !hasFiniteControlFlow(copy.getBody()))
    while (threadActivationControlFlow(copy.getBody())) {
      if (failed(canonicalizeActivationControlFlow(copy)))
        return {};
    }
  // Aggressive CFG simplification before this view (not the canonicalization
  // above) may have shared a case tail using reference arguments. Recover its
  // static aliases before any memory/value summary is derived;
  // otherwise section recovery can mistake that lost precision for feedback
  // and discard the owner before interleaving analysis ever sees it.
  specializeStaticHandleTails(copy.getBody());
  if (trace)
    trace(resume ? ActivationPreparationOptions::TracePhase::Resume
                 : ActivationPreparationOptions::TracePhase::Initial,
          copy);
  return owner;
}

/// Give every top-level loop a dedicated entry block and one landing block
/// per exit edge, so the blocks around a loop bound it as a unit. Canonical
/// pass-through forwarding otherwise lets a loop exit straight into the next
/// loop's header, fusing both loops into one scheduling unit. Entry operands
/// pass through unchanged, keeping a constant induction start visible.
void separateTopLevelLoops(sim::SimFuncOp function) {
  Region &body = function.getBody();
  SmallVector<SmallVector<Block *>> loops;
  for (auto scc = llvm::scc_begin(&body); !scc.isAtEnd(); ++scc)
    if (scc.hasCycle())
      loops.emplace_back(scc->begin(), scc->end());
  OpBuilder builder(function.getContext());
  auto splitEdge = [&](Block *from, unsigned successor) {
    auto branch = cast<BranchOpInterface>(from->getTerminator());
    Block *to = from->getTerminator()->getSuccessor(successor);
    SmallVector<Value> operands(
        branch.getSuccessorOperands(successor).getForwardedOperands());
    auto *landing = new Block;
    body.getBlocks().insert(to->getIterator(), landing);
    builder.setInsertionPointToEnd(landing);
    cf::BranchOp::create(builder, from->getTerminator()->getLoc(), to,
                         operands);
    branch.getSuccessorOperands(successor).erase(0, operands.size());
    from->getTerminator()->setSuccessor(landing, successor);
  };
  for (const auto &loop : loops) {
    DenseSet<Block *> members(loop.begin(), loop.end());
    SmallVector<std::pair<Block *, unsigned>> entries, exits;
    for (Block *block : loop) {
      for (auto it = block->pred_begin(); it != block->pred_end(); ++it)
        if (!members.contains(*it))
          entries.push_back({*it, it.getSuccessorIndex()});
      for (auto [index, next] : llvm::enumerate(block->getSuccessors()))
        if (!members.contains(next))
          exits.push_back({block, unsigned(index)});
    }
    // A loop already entered by the sole edge of a straight-line block has
    // its boundary; several entries would need a merged entry block.
    if (entries.size() == 1 && entries.front().first->getNumSuccessors() > 1)
      splitEdge(entries.front().first, entries.front().second);
    for (auto [block, index] : exits)
      splitEdge(block, index);
  }
}

// A shared case suffix can occur before the first publication on one path
// and after it on another. Specialize acyclic tails by incoming edge, keeping
// exactly one dynamic execution of each operation. Loops remain untouched.
bool specializeConditionalTails(Operation *entry, Block *join,
                                unsigned &growthBudget) {
  Block *start = entry->getBlock();
  SmallVector<Block *> vertices{start};
  DenseSet<Block *> inside{start};
  DenseMap<Block *, SmallVector<Block *>> edges;
  for (unsigned index = 0; index < vertices.size(); ++index) {
    Block *block = vertices[index];
    if (block == join)
      continue;
    for (Block *next : block->getSuccessors()) {
      edges[block].push_back(next);
      if (inside.insert(next).second)
        vertices.push_back(next);
    }
    if (vertices.size() > 256)
      return false;
  }
  auto components =
      computeStronglyConnectedComponents<Block *>(vertices, edges);
  for (const auto &component : components)
    if (component.size() > 1 ||
        llvm::is_contained(edges.lookup(component.front()), component.front()))
      return false;
  bool changed = false;
  // Tarjan returns reverse topological order. Specializing inner joins first
  // makes enclosing tails single-entry without enumerating complete paths.
  for (const auto &component : components) {
    Block *root = component.front();
    if (root == start || root == join || root->hasOneUse())
      continue;
    SmallVector<std::pair<Operation *, unsigned>> incoming;
    for (auto it = root->pred_begin(); it != root->pred_end(); ++it)
      incoming.emplace_back((*it)->getTerminator(), it.getSuccessorIndex());
    if (incoming.size() < 2 || incoming.size() > 32 ||
        llvm::any_of(incoming, [](auto edge) {
          return !isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp>(edge.first);
        }))
      continue;
    SmallVector<Block *> tail{root};
    DenseSet<Block *> members{root};
    unsigned operations = 0;
    for (unsigned index = 0; index < tail.size(); ++index) {
      Block *block = tail[index];
      operations += block->getOperations().size();
      for (Block *next : block->getSuccessors())
        if (next != join && members.insert(next).second)
          tail.push_back(next);
    }
    if (operations > growthBudget / incoming.size())
      continue;
    if (llvm::any_of(tail, [&](Block *block) {
          if (block != root &&
              llvm::any_of(block->getPredecessors(), [&](Block *from) {
                return !members.contains(from);
              }))
            return true;
          auto escapes = [&](Value value) {
            return llvm::any_of(value.getUsers(), [&](Operation *user) {
              return !members.contains(user->getBlock());
            });
          };
          return llvm::any_of(block->getArguments(), escapes) ||
                 llvm::any_of(*block, [&](Operation &op) {
                   return op.getNumRegions() ||
                          llvm::any_of(op.getResults(), escapes);
                 });
        }))
      continue;
    growthBudget -= operations * incoming.size();
    Region &body = *join->getParent();
    for (auto [term, index] : incoming) {
      IRMapping mapping;
      auto operands = cast<BranchOpInterface>(term).getSuccessorOperands(index);
      mapping.map(root->getArguments(), operands.getForwardedOperands());
      for (Block *block : tail) {
        auto *copy = new Block;
        body.getBlocks().insert(join->getIterator(), copy);
        mapping.map(block, copy);
        if (block != root)
          for (BlockArgument argument : block->getArguments())
            mapping.map(argument, copy->addArgument(argument.getType(),
                                                    argument.getLoc()));
      }
      for (Block *block : tail) {
        OpBuilder builder = OpBuilder::atBlockEnd(mapping.lookup(block));
        for (Operation &op : *block)
          builder.clone(op, mapping);
      }
      operands.erase(0, operands.size());
      term->setSuccessor(mapping.lookup(root), index);
    }
    for (Block *block : tail)
      block->dropAllDefinedValueUses();
    for (Block *block : tail)
      block->dropAllReferences();
    for (Block *block : tail)
      block->erase();
    changed = true;
  }
  return changed;
}

// Align the first publication on each path at a common continuation. The
// continuation dispatches on a saved path identity, never on a fresh load of
// the source condition. Live prefix values are explicit SSA continuation
// arguments, preserving the original memory snapshots across a handoff. This
// bounded normalization neither repeats a load nor unrolls an induction loop.
Operation *exposePublicationFrontier(Operation *entry, Block *join,
                                     const ActivationMemoryAnalysis &memory,
                                     unsigned &budget,
                                     ActivationFrontierTrace trace) {
  if (join->getNumArguments()) {
    if (trace)
      trace("join arguments", join->getArgument(0));
    return nullptr;
  }
  if (!isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp>(entry))
    return nullptr;
  DenseSet<Operation *> prefix{entry};
  SmallVector<Operation *> prefixOrder{entry};
  DenseSet<Block *> blocks;
  SmallVector<Block *> pending(entry->getSuccessors());
  SmallVector<Operation *> cuts;
  SmallVector<std::pair<Operation *, unsigned>> emptyPaths;
  auto successors = [&](Operation *term) {
    for (auto [index, next] : llvm::enumerate(term->getSuccessors()))
      if (next == join)
        emptyPaths.emplace_back(term, index);
      else
        pending.push_back(next);
  };
  pending.clear();
  successors(entry);
  unsigned work = 0;
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    if (!blocks.insert(block).second)
      continue;
    if (blocks.size() > 1024)
      return nullptr;
    bool cut = false;
    for (Operation &op : *block) {
      if (++work > 4096 || !budget || op.getNumRegions())
        return nullptr;
      --budget;
      prefix.insert(&op);
      prefixOrder.push_back(&op);
      if (memory.getWrites().contains(&op)) {
        cuts.push_back(&op);
        cut = true;
        break;
      }
    }
    if (!cut) {
      if (!isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp>(
              block->getTerminator()))
        return nullptr;
      successors(block->getTerminator());
    }
  }
  if (cuts.empty() || cuts.size() > 32)
    return nullptr;
  // Pure definitions can share an original branch prefix with a publication
  // while their operands are already available at the region entry. Hoist
  // only those computations, never a load or a new memory snapshot.
  DominanceInfo dominance(entry->getParentOp());
  unsigned hoistDepth = 0;
  auto hoist = [&](Operation *op, auto &hoist) -> bool {
    if (!prefix.contains(op))
      return true;
    if (op == entry || hoistDepth == 128 || !budget ||
        !isMemoryEffectFree(op) || !isSpeculatable(op))
      return false;
    --budget;
    ++hoistDepth;
    llvm::scope_exit restoreDepth([&] { --hoistDepth; });
    for (Value operand : op->getOperands()) {
      Operation *definition = operand.getDefiningOp();
      if (definition && prefix.contains(definition)) {
        if (!hoist(definition, hoist))
          return false;
      } else if (!dominance.dominates(operand, entry))
        return false;
    }
    op->moveBefore(entry);
    prefix.erase(op);
    return true;
  };
  struct Snapshot {
    Value value;
    SmallVector<OpOperand *> uses;
    Value initial, argument;
  };
  SmallVector<Snapshot> snapshots;
  unsigned snapshotBits = 0;
  auto preserve = [&](Value value) {
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : value.getUses())
      if (!prefix.contains(use.getOwner()))
        uses.push_back(&use);
    if (uses.empty())
      return true;
    auto width = sim::getPackedWidth(value.getType());
    if (!width || *width > 65536 || snapshots.size() == 32 ||
        snapshotBits + *width > 65536) {
      if (trace)
        trace("unsupported continuation snapshot", value);
      return false;
    }
    snapshotBits += *width;
    snapshots.push_back({value, std::move(uses), {}, {}});
    return true;
  };
  for (Operation *op : prefixOrder)
    if (llvm::any_of(op->getUsers(),
                     [&](Operation *user) { return !prefix.contains(user); }) &&
        !hoist(op, hoist))
      for (Value value : op->getResults())
        if (!preserve(value))
          return nullptr;
  for (Block *block : blocks)
    for (BlockArgument argument : block->getArguments())
      if (!preserve(argument))
        return nullptr;
  // A shared suffix must not reenter another path's prefix (nor a loop).
  DenseSet<Block *> suffix;
  pending.clear();
  for (Operation *cut : cuts) {
    for (Operation *op = cut->getNextNode(); op; op = op->getNextNode())
      if (prefix.contains(op))
        return nullptr;
    llvm::append_range(pending, cut->getBlock()->getSuccessors());
  }
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    if (block == join || !suffix.insert(block).second)
      continue;
    if (blocks.contains(block) || ++work > 4096) {
      if (trace)
        trace("shared prefix/suffix or suffix budget", {});
      return nullptr;
    }
    llvm::append_range(pending, block->getSuccessors());
  }
  OpBuilder builder(entry);
  Location location = entry->getLoc();
  DenseMap<Type, Value> zeros;
  for (Snapshot &snapshot : snapshots) {
    Type type = snapshot.value.getType();
    Value &zero = zeros[type];
    if (!zero) {
      Type scalar = sim::getPackedScalarType(type);
      auto width = sim::getPackedWidth(type);
      if (!scalar || !width)
        return nullptr;
      if (isa<IntegerType>(scalar))
        zero = arith::ConstantOp::create(
            builder, location, scalar,
            builder.getIntegerAttr(scalar, APInt(*width, 0)));
      else
        zero = sim::SimLogicConstantOp::create(
            builder, location, scalar,
            builder.getIntegerAttr(builder.getIntegerType(*width),
                                   APInt(*width, 0)),
            builder.getIntegerAttr(builder.getIntegerType(*width),
                                   APInt(*width, 0)));
      if (type != scalar)
        zero = sim::SimPackedUnflattenOp::create(builder, location, type, zero);
    }
    snapshot.initial = zero;
  }
  // Incoming paths which never defined a snapshot cannot reach its original
  // uses. Supply a typed zero on those inactive lanes, and dispatch with the
  // saved path identity before using any captured value. Available values
  // retain their exact SSA snapshot; no canonical load is repeated.
  auto captureAt = [&](Operation *point) {
    SmallVector<Value> values;
    for (const Snapshot &snapshot : snapshots)
      values.push_back(dominance.dominates(snapshot.value, point)
                           ? snapshot.value
                           : snapshot.initial);
    return values;
  };
  SmallVector<SmallVector<Value>> capturedCuts, capturedEmpty;
  for (Operation *cut : cuts)
    capturedCuts.push_back(captureAt(cut));
  for (auto [term, index] : emptyPaths)
    capturedEmpty.push_back(captureAt(term));
  Region &body = *join->getParent();
  auto *checkpoint = new Block;
  body.getBlocks().insert(join->getIterator(), checkpoint);
  Value path = checkpoint->addArgument(builder.getI32Type(), location);
  for (Snapshot &snapshot : snapshots)
    snapshot.argument =
        checkpoint->addArgument(snapshot.value.getType(), location);
  SmallVector<APInt> cases;
  SmallVector<Block *> continuations;
  SmallVector<ValueRange> operands;
  for (auto [index, cut] : llvm::enumerate(cuts)) {
    Block *from = cut->getBlock();
    Block *continuation = from->splitBlock(std::next(cut->getIterator()));
    builder.setInsertionPointToEnd(from);
    unsigned id = cases.size() + 1;
    Value token = arith::ConstantIntOp::create(builder, location, id, 32);
    SmallVector<Value> captured{token};
    llvm::append_range(captured, capturedCuts[index]);
    cf::BranchOp::create(builder, location, checkpoint, captured);
    cases.emplace_back(32, id);
    continuations.push_back(continuation);
    operands.push_back(ValueRange{});
  }
  for (auto [pathIndex, edgePoint] : llvm::enumerate(emptyPaths)) {
    auto [term, index] = edgePoint;
    builder.setInsertionPoint(term);
    Value token = arith::ConstantIntOp::create(builder, location, 0, 32);
    auto edge = cast<BranchOpInterface>(term).getSuccessorOperands(index);
    SmallVector<Value> captured{token};
    llvm::append_range(captured, capturedEmpty[pathIndex]);
    edge.append(captured);
    term->setSuccessor(checkpoint, index);
  }
  for (const Snapshot &snapshot : snapshots)
    for (OpOperand *use : snapshot.uses)
      use->set(snapshot.argument);
  builder.setInsertionPointToEnd(checkpoint);
  return cf::SwitchOp::create(builder, location, path, join, ValueRange{},
                              cases, continuations, operands);
}

bool equivalentActivations(sim::SimFuncOp lhs, sim::SimFuncOp rhs) {
  // CFG block order is not dominance order. Register corresponding SSA
  // definitions before comparing operands, including definitions in a loop
  // header printed after one of its dominated exit blocks.
  auto definitions = [](sim::SimFuncOp function) {
    SmallVector<Value> values;
    function.walk([&](Operation *op) {
      llvm::append_range(values, op->getResults());
      for (Region &region : op->getRegions())
        for (Block &block : region)
          llvm::append_range(values, block.getArguments());
    });
    return values;
  };
  auto left = definitions(lhs), right = definitions(rhs);
  if (left.size() != right.size())
    return false;
  IRMapping mapping;
  mapping.map(left, right);
  return OperationEquivalence::isEquivalentTo(
      lhs, rhs,
      [&](Value a, Value b) {
        return success(mapping.lookupOrDefault(a) == b);
      },
      nullptr, OperationEquivalence::IgnoreLocations);
}
} // namespace

PreparedActivation
prepareActivation(sim::SimFuncOp function,
                  const ActivationPreparationOptions &options) {
  PreparedActivation prepared;
  prepared.source = function;
  prepared.symbols = options.symbols;
  if (function.isExternal() || !function.getFunctionType().getResults().empty())
    return prepared;
  Operation *&suspension = prepared.suspension;
  auto &reason = prepared.reason;
  using FailureReason = ActivationFailureReason;
  unsigned waits = 0;
  bool returns = false;
  function.walk([&](Operation *op) {
    returns |= isa<sim::SimReturnOp>(op);
    if (sim::isSuspensionOp(op)) {
      ++waits;
      prepared.suspension = op;
    }
  });
  if (returns || waits != 1 ||
      !isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(suspension))
    return prepared;
  if (auto any = dyn_cast<sim::SimSuspendAnyOp>(suspension))
    if (llvm::any_of(any.getEdges(), [](int32_t edge) {
          return edge != static_cast<int32_t>(sim::EdgeKind::Change);
        }))
      return prepared;
  IRMapping initialMap, resumeMap;
  auto initial =
      cloneActivation(function, suspension, false, initialMap, options.trace,
                      options.controlFlow, options.controls);
  auto resumed =
      cloneActivation(function, suspension, true, resumeMap, options.trace,
                      options.controlFlow, options.controls);
  if (!initial || !resumed ||
      !equivalentActivations(initial.get(), resumed.get())) {
    reason = FailureReason::InitialResumeEquivalence;
    return prepared;
  }
  if (!hasFiniteControlFlow(initial->getBody())) {
    reason = FailureReason::Termination;
    return prepared;
  }
  separateTopLevelLoops(*initial);
  prepared.view = std::move(initial);
  prepared.reason = ActivationFailureReason::None;
  return prepared;
}

std::optional<PreparedActivation>
prepareActivationFrontiers(const ActivationRegionAnalysis &activation,
                           const HandleDataflowAnalysis &handles,
                           ActivationFrontierTrace trace) {
  if (!activation.isValid())
    return std::nullopt;
  unsigned operations = 0;
  if (activation.getActivationFunction()
          .walk([&](Operation *) {
            return ++operations > 4096 ? WalkResult::interrupt()
                                       : WalkResult::advance();
          })
          .wasInterrupted())
    return std::nullopt;
  IRMapping mapping;
  OwningOpRef<sim::SimFuncOp> copy(
      cast<sim::SimFuncOp>(activation.getActivationFunction()->clone(mapping)));
  DenseSet<Block *> conditionalBlocks;
  for (const auto &node : activation.getNodes())
    for (Block *block : node.blocks)
      conditionalBlocks.insert(mapping.lookup(block));
  bool changed =
      specializeStaticHandleTails(copy->getBody(), [&](Block *block) {
        return conditionalBlocks.contains(block);
      });
  unsigned tailBudget = 4096;
  for (const auto &node : activation.getNodes())
    if (node.isRegion())
      changed |=
          specializeConditionalTails(mapping.lookup(node.operation),
                                     mapping.lookup(node.join), tailBudget);
  if (changed)
    propagateActivationValueRoots(*copy);
  ActivationMemoryAnalysis effects(
      *copy, handles, 65536, ActivationMemoryAnalysis::DependencyMode::Accesses,
      activation.getSymbolTable());
  if (!effects.isValid()) {
    if (trace)
      trace("normalized memory effects", {});
    return std::nullopt;
  }
  unsigned budget = 65536, frontiers = 0;
  for (const auto &node : activation.getNodes()) {
    if (!node.isRegion())
      continue;
    Operation *entry = mapping.lookup(node.operation);
    while (frontiers < 64) {
      Operation *next = exposePublicationFrontier(
          entry, mapping.lookup(node.join), effects, budget, trace);
      if (!next)
        break;
      entry = next;
      ++frontiers;
      changed = true;
    }
  }
  if (!changed)
    return std::nullopt;
  // Do not canonicalize this checkpoint back into the original case tree.
  // Its saved dispatch is precisely the legal statement suspension boundary
  // that the coarse region graph could not express.
  separateTopLevelLoops(*copy);
  PreparedActivation prepared;
  prepared.view = std::move(copy);
  prepared.source = activation.getSourceFunction();
  prepared.symbols = activation.getSymbolTable();
  prepared.suspension = activation.getSuspension();
  prepared.sourceActivation = activation.getSourceActivation();
  prepared.reason = ActivationFailureReason::None;
  return prepared;
}
} // namespace talos::analysis
