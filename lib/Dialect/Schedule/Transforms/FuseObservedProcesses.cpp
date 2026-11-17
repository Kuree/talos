//===- FuseObservedProcesses.cpp - One Observed activation per clock edge ===//
//
// A concurrent assertion lowers to a process that waits for its clock edge
// and resumes in the Observed region, where its property expression is
// evaluated on sampled values (IEEE 1800-2023 4.4.2.5, 16.5.1). Pass/fail
// code runs in spawned processes. A design with many assertions on one clock
// otherwise pays a scheduler resumption per assertion and edge.
//
// Processes that wait for the same edge of the same root and resume in the
// Observed region become one process. It runs every member's start-up code
// in turn, waits once, and then runs each member's activation in turn. Every
// member is waiting whenever the fused process waits, because each activation
// ends at its member's single wait. So one edge resumes all members, as it
// did before. Running them back to back is one ordering of their events
// (4.7). A member's loop-carried values flow through an exit block of its
// own, which dominates every later member's code and the shared wait.
//
// Members must not depend on their process identity, directly or through
// the functions they call: no process handle, block activation, disable,
// monitor, termination, or return. Nor may they, or code they call or spawn,
// use random state: each process has its own random number generator and
// seeds the processes it creates from it (18.14.1), so merged members would
// share one stream. Operations with unknown effects are treated as using
// both. Members write only private state, so none can change the clock that
// the shared wait observes. The root must spawn each member exactly once and
// drop the handle. Requires VPI off, since a VPI client can distinguish the
// processes.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/StringMap.h"

#include <functional>

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMFUSEOBSERVEDPROCESSESPASS
#include "talos/Dialect/Schedule/Transforms/Passes.h.inc"

namespace {
struct Member {
  sim::SimFuncOp function;
  sim::SimSpawnOp spawn;
  sim::SimSuspendEdgeOp suspend;
  Block *wait = nullptr;
  /// Reachable blocks other than the wait, in reverse post-order, split into
  /// the start-up code before the first wait and the activation after it.
  SmallVector<Block *> preamble, body;
  SmallVector<unsigned> fusedArguments;
};

/// What a function, or what it calls (and, for random state, spawns), may do.
struct Traits {
  bool processDependent = false;
  bool randomOrOpaque = false;
  bool writesDesign = false;
};

class TalosSimFuseObservedProcessesPass final
    : public impl::TalosSimFuseObservedProcessesPassBase<
          TalosSimFuseObservedProcessesPass> {
public:
  using Base::Base;
  void runOnOperation() override;
};

void TalosSimFuseObservedProcessesPass::runOnOperation() {
  sim::SimDesignOp design = getOperation();
  ModuleOp module = design->getParentOfType<ModuleOp>();
  bool report = module && native::has<native::DebugTiming>(module);
  if (schedule::ComputeGraphAttr graph = design.getComputeGraphAttr();
      graph && graph.getVpi() != schedule::ComputeVPIMode::Off)
    return;

  sim::SimFuncOp root;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>())
    if (function.getEntryKind() == sim::EntryKind::RootInitializer)
      root = function;
  if (!root)
    return;
  DenseMap<StringAttr, SmallVector<sim::SimSpawnOp>> spawns;
  design.walk([&](sim::SimSpawnOp spawn) {
    spawns[spawn.getCalleeAttr().getAttr()].push_back(spawn);
  });
  // Every symbol reference other than the root spawn keeps a member alive.
  DenseMap<StringAttr, unsigned> symbolUses;
  if (auto uses = analysis::getSymbolUsesConcurrently(&design.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      ++symbolUses[use.getSymbolRef().getRootReference()];

  SymbolTable symbols(design);
  analysis::HandleDataflowAnalysis provenance(design);
  provenance.prepare(design);

  // `top` is a member, whose single wait is counted separately. A callee runs
  // on behalf of the calling process, so a suspension there is the member's;
  // a callee's return is not.
  DenseMap<Operation *, Traits> traitCache;
  std::function<Traits(sim::SimFuncOp, bool)> traitsOf =
      [&](sim::SimFuncOp function, bool top) -> Traits {
    if (!top) {
      if (auto found = traitCache.find(function); found != traitCache.end())
        return found->second;
      // A recursive cycle stays conservative.
      traitCache[function] = Traits{true, true, true};
    }
    Traits traits;
    std::optional<analysis::HandleFacts> facts;
    auto calleeOf = [&](FlatSymbolRefAttr callee) {
      return symbols.lookup<sim::SimFuncOp>(callee.getAttr());
    };
    function.walk([&](Operation *operation) {
      if (operation == function.getOperation())
        return;
      if (auto spawn = dyn_cast<sim::SimSpawnOp>(operation)) {
        // A child has its own identity, but it is seeded from its parent's
        // random number generator (18.14.1).
        sim::SimFuncOp child = calleeOf(spawn.getCalleeAttr());
        traits.randomOrOpaque |= !child || child.isExternal() ||
                                 traitsOf(child, false).randomOrOpaque;
        return;
      }
      if (auto call = dyn_cast<sim::SimCallOp>(operation)) {
        sim::SimFuncOp callee = calleeOf(call.getCalleeAttr());
        if (!callee || callee.isExternal()) {
          traits = Traits{true, true, true};
          return;
        }
        Traits inner = traitsOf(callee, false);
        traits.processDependent |= inner.processDependent;
        traits.randomOrOpaque |= inner.randomOrOpaque;
        traits.writesDesign |= inner.writesDesign;
        return;
      }
      if (sim::isSuspensionOp(operation)) {
        traits.processDependent |= !top;
        return;
      }
      if (isa<sim::SimReturnOp>(operation)) {
        traits.processDependent |= top;
        return;
      }
      StringRef name = operation->getName().getStringRef();
      if (name.starts_with("simulation.monitor.") ||
          name.starts_with("simulation.coverage") ||
          isa<sim::SimTerminationRequestedOp>(operation))
        traits.processDependent = true;
      std::optional<SmallVector<MemoryEffects::EffectInstance>> effects =
          getEffectsRecursively(operation);
      if (!effects) {
        traits = Traits{true, true, true};
        return;
      }
      for (const MemoryEffects::EffectInstance &effect : *effects) {
        SideEffects::Resource *resource = effect.getResource();
        if (isa<sim::ProcessResource>(resource)) {
          traits.processDependent = true;
        } else if (isa<sim::RNGResource, sim::ExternalResource>(resource)) {
          traits.randomOrOpaque = true;
        } else if (isa<MemoryEffects::Write>(effect.getEffect()) &&
                   isa<sim::StorageResource, sim::NetResource>(resource)) {
          // Stores to private slots are the member's own state.
          if (auto store = dyn_cast<sim::SimRefStoreOp>(operation)) {
            if (!facts)
              facts = provenance.derive(function);
            auto fact = facts->find(store.getReference());
            if (fact != facts->end() &&
                fact->second.resource == schedule::ComputeResourceKind::Local)
              continue;
          }
          traits.writesDesign = true;
        }
      }
    });
    if (!top)
      traitCache[function] = traits;
    return traits;
  };

  llvm::StringMap<unsigned> rejections;
  auto reject = [&](StringRef reason) { ++rejections[reason]; };
  // Group by the exact waited root and edge, and by everything else that the
  // fused process takes from its first member. Equal handles make equal
  // events; copies of a clock are not merged here.
  using Key =
      std::tuple<uint64_t, unsigned, unsigned, unsigned, unsigned, Attribute>;
  llvm::MapVector<Key, SmallVector<Member>> groups;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getHomeRegion() != sim::EventRegion::Observed)
      continue;
    Member member;
    member.function = function;
    auto found = spawns.find(function.getSymNameAttr());
    if (found == spawns.end() || found->second.size() != 1 ||
        found->second.front()->getBlock() != &root.getBody().front() ||
        !found->second.front().getResult().use_empty() ||
        symbolUses.lookup(function.getSymNameAttr()) != 1) {
      reject("spawn");
      continue;
    }
    member.spawn = found->second.front();
    unsigned suspensions = 0;
    function.walk([&](Operation *operation) {
      if (!sim::isSuspensionOp(operation))
        return;
      ++suspensions;
      member.suspend = dyn_cast<sim::SimSuspendEdgeOp>(operation);
    });
    std::optional<sim::EventRegion> resume =
        member.suspend ? member.suspend.getResumeRegion() : std::nullopt;
    if (suspensions != 1 || !member.suspend || !resume ||
        *resume != sim::EventRegion::Observed) {
      reject("wait");
      continue;
    }
    Traits traits = traitsOf(function, /*top=*/true);
    if (traits.processDependent) {
      reject("process-dependent operation");
      continue;
    }
    if (traits.randomOrOpaque) {
      reject("random state or opaque effect");
      continue;
    }
    if (traits.writesDesign) {
      reject("design write");
      continue;
    }
    // The wait block holds only the wait. Start-up code reaches it without
    // passing through it again, and the activation returns to it.
    member.wait = member.suspend->getBlock();
    Block *entry = &function.getBody().front();
    Block *continuation = member.suspend.getContinuation();
    if (member.wait->getOperations().size() != 1 || entry == member.wait ||
        continuation == member.wait) {
      reject("shape");
      continue;
    }
    DenseSet<Block *> before, after;
    auto reach = [&](Block *start, DenseSet<Block *> &seen) {
      SmallVector<Block *> pending{start};
      while (!pending.empty()) {
        Block *block = pending.pop_back_val();
        if (block == member.wait || !seen.insert(block).second)
          continue;
        llvm::append_range(pending, block->getSuccessors());
      }
    };
    reach(entry, before);
    reach(continuation, after);
    bool waits = llvm::any_of(before, [&](Block *block) {
      return llvm::is_contained(block->getSuccessors(), member.wait);
    });
    if (!waits || llvm::any_of(after, [&](Block *block) {
          return before.contains(block);
        })) {
      reject("shape");
      continue;
    }
    for (Block *block : llvm::ReversePostOrderTraversal<Block *>(entry)) {
      if (before.contains(block))
        member.preamble.push_back(block);
      else if (after.contains(block))
        member.body.push_back(block);
    }
    analysis::HandleFacts facts = provenance.derive(function);
    auto fact = facts.find(member.suspend.getWatched());
    if (fact == facts.end() || !fact->second.descriptor ||
        fact->second.dynamic || fact->second.low != 0 ||
        fact->second.width != fact->second.rootWidth) {
      reject("watched root");
      continue;
    }
    std::optional<uint64_t> watched =
        analysis::ActivationMemoryAnalysis::getRoot(fact->second.resource,
                                                    *fact->second.descriptor);
    if (!watched) {
      reject("watched root");
      continue;
    }
    // The shared wait is a copy of the first member's: its discardable
    // attributes must agree. The continuation site is inherent.
    Key key{*watched,
            static_cast<unsigned>(member.suspend.getEdge()),
            static_cast<unsigned>(function.getEntryKind()),
            static_cast<unsigned>(function.getDomain()),
            static_cast<unsigned>(
                schedule::has<schedule::Field::StartsWithoutWaiting>(function)),
            member.suspend->getDiscardableAttrDictionary()};
    groups[key].push_back(std::move(member));
  }

  unsigned kernels = 0, fused = 0;
  for (auto &group : groups) {
    const Key &key = group.first;
    SmallVector<Member> &members = group.second;
    if (members.size() < 2) {
      reject("single member");
      continue;
    }
    // Captures: the union of the spawn operands. Equal operands with equal
    // argument attributes share one argument.
    SmallVector<Value> operands;
    SmallVector<Type> inputTypes;
    SmallVector<DictionaryAttr> argumentAttrs;
    DenseMap<std::pair<Value, Attribute>, unsigned> indices;
    sim::SimSpawnOp insertion = members.front().spawn;
    for (Member &member : members) {
      if (insertion->isBeforeInBlock(member.spawn))
        insertion = member.spawn;
      Block &entry = member.function.getBody().front();
      for (auto [argument, operand] :
           llvm::zip_equal(entry.getArguments(), member.spawn.getOperands())) {
        DictionaryAttr attrs =
            member.function.getArgAttrDict(argument.getArgNumber());
        auto [found, inserted] =
            indices.try_emplace({operand, attrs}, operands.size());
        if (inserted) {
          operands.push_back(operand);
          inputTypes.push_back(argument.getType());
          argumentAttrs.push_back(attrs);
        }
        member.fusedArguments.push_back(found->second);
      }
    }

    Member &first = members.front();
    Location location = first.function.getLoc();
    OpBuilder builder = OpBuilder::atBlockEnd(&design.getBody().front());
    SmallVector<NamedAttribute> attributes;
    if (Attribute region = first.function.getHomeRegionAttr())
      attributes.push_back(
          builder.getNamedAttr(first.function.getHomeRegionAttrName(), region));
    if (Attribute domain = first.function.getDomainAttr())
      attributes.push_back(
          builder.getNamedAttr(first.function.getDomainAttrName(), domain));
    if (IntegerAttr codeUnit = first.function.getCodeUnitIdAttr())
      attributes.push_back(builder.getNamedAttr(
          first.function.getCodeUnitIdAttrName(), codeUnit));
    unsigned counter = 0;
    SmallString<48> base;
    ("__talos_observed_" + Twine(std::get<0>(key)) + "_" +
     Twine(std::get<1>(key)))
        .toVector(base);
    SmallString<48> name = SymbolTable::generateSymbolName<48>(
        base, [&](StringRef candidate) { return symbols.lookup(candidate); },
        counter);
    sim::SimFuncOp kernel = sim::SimFuncOp::create(
        builder, location, name,
        FunctionType::get(design.getContext(), inputTypes, TypeRange{}),
        first.function.getEntryKind(), attributes, argumentAttrs);
    if (std::get<4>(key))
      schedule::set<schedule::Field::StartsWithoutWaiting>(
          kernel, builder.getUnitAttr());
    symbols.insert(kernel);
    SymbolTable::setSymbolVisibility(kernel, SymbolTable::Visibility::Private);

    // Blocks: entry; each member's start-up code followed by its start exit;
    // the shared wait carrying every member's loop values; the activation;
    // each member's body followed by its exit.
    Block &entry = kernel.getBody().front();
    std::vector<IRMapping> mappings(members.size());
    SmallVector<Block *> starts, startExits, exits;
    auto createBlocks = [&](ArrayRef<Block *> sources, IRMapping &mapping) {
      for (Block *source : sources) {
        Block *cloned = new Block;
        kernel.getBody().push_back(cloned);
        mapping.map(source, cloned);
        // The entry block's arguments are the captures, mapped below.
        if (!source->isEntryBlock())
          for (BlockArgument argument : source->getArguments())
            mapping.map(argument, cloned->addArgument(argument.getType(),
                                                      argument.getLoc()));
      }
    };
    auto exitFor = [&](Member &member) {
      Block *exit = new Block;
      kernel.getBody().push_back(exit);
      for (BlockArgument argument : member.wait->getArguments())
        exit->addArgument(argument.getType(), argument.getLoc());
      return exit;
    };
    for (auto [index, member] : llvm::enumerate(members)) {
      IRMapping &mapping = mappings[index];
      for (auto [argument, fusedIndex] :
           llvm::zip_equal(member.function.getBody().front().getArguments(),
                           member.fusedArguments))
        mapping.map(argument, entry.getArgument(fusedIndex));
      createBlocks(member.preamble, mapping);
      starts.push_back(mapping.lookup(member.preamble.front()));
      startExits.push_back(exitFor(member));
    }
    Block *wait = new Block;
    kernel.getBody().push_back(wait);
    Block *activation = new Block;
    kernel.getBody().push_back(activation);
    for (auto [index, member] : llvm::enumerate(members)) {
      for (BlockArgument argument : member.wait->getArguments())
        mappings[index].map(
            argument, wait->addArgument(argument.getType(), argument.getLoc()));
      createBlocks(member.body, mappings[index]);
      exits.push_back(exitFor(member));
    }
    // Blocks are cloned in reverse post-order, so every definition is cloned
    // before its uses.
    auto cloneOperations = [&](ArrayRef<Block *> sources, IRMapping &mapping) {
      for (Block *source : sources) {
        builder.setInsertionPointToEnd(mapping.lookup(source));
        for (Operation &operation : *source)
          builder.clone(operation, mapping);
      }
    };

    // Start-up code. A branch to the member's wait ends its start-up.
    builder.setInsertionPointToEnd(&entry);
    cf::BranchOp::create(builder, location, starts.front());
    for (auto [index, member] : llvm::enumerate(members)) {
      mappings[index].map(member.wait, startExits[index]);
      cloneOperations(member.preamble, mappings[index]);
      builder.setInsertionPointToEnd(startExits[index]);
      if (index + 1 != members.size()) {
        cf::BranchOp::create(builder, location, starts[index + 1]);
        continue;
      }
      // Every start exit dominates the last one.
      SmallVector<Value> initial;
      for (Block *exit : startExits)
        llvm::append_range(initial, exit->getArguments());
      cf::BranchOp::create(builder, location, wait, initial);
    }

    // The shared wait resumes the activation without forwarded values: the
    // wait block's arguments dominate every member body.
    builder.setInsertionPointToEnd(wait);
    auto suspend = cast<sim::SimSuspendEdgeOp>(
        builder.clone(*first.suspend, mappings.front()));
    suspend->setSuccessor(activation, 0);
    suspend.getContinuationOperandsMutable().clear();

    auto enter = [&](OpBuilder &at, unsigned index) {
      Member &member = members[index];
      SmallVector<Value> forwarded;
      for (Value value : member.suspend.getContinuationOperands())
        forwarded.push_back(mappings[index].lookupOrDefault(value));
      cf::BranchOp::create(
          at, location,
          mappings[index].lookup(member.suspend.getContinuation()), forwarded);
    };
    builder.setInsertionPointToEnd(activation);
    enter(builder, 0);
    for (auto [index, member] : llvm::enumerate(members)) {
      // A branch back to the member's wait ends its activation.
      mappings[index].map(member.wait, exits[index]);
      cloneOperations(member.body, mappings[index]);
      builder.setInsertionPointToEnd(exits[index]);
      if (index + 1 != members.size()) {
        enter(builder, index + 1);
        continue;
      }
      // Every exit dominates the last one, so each member's next loop
      // values reach the shared wait.
      SmallVector<Value> next;
      for (Block *exit : exits)
        llvm::append_range(next, exit->getArguments());
      cf::BranchOp::create(builder, location, wait, next);
    }

    builder.setInsertionPoint(insertion);
    sim::SimSpawnOp::create(builder, location, kernel.getSymNameAttr(),
                            operands, ArrayAttr{}, ArrayAttr{});
    for (Member &member : members) {
      member.spawn.erase();
      symbols.erase(member.function);
    }
    if (report)
      llvm::errs() << "talos observed kernel: " << kernel.getSymName()
                   << " members=" << members.size() << '\n';
    ++kernels;
    fused += members.size();
  }
  if (report) {
    llvm::errs() << "talos observed kernels: kernels=" << kernels
                 << " members=" << fused << '\n';
    SmallVector<std::pair<StringRef, unsigned>> sorted;
    for (const auto &entry : rejections)
      sorted.emplace_back(entry.getKey(), entry.getValue());
    llvm::sort(sorted);
    for (auto [reason, count] : sorted)
      llvm::errs() << "talos observed kernel rejection: " << reason << " = "
                   << count << '\n';
  }
  if (kernels)
    design.removeComputeGraphAttr();
}

} // namespace
} // namespace talos
