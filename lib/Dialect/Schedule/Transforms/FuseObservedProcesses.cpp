//===- FuseObservedProcesses.cpp - One Observed activation per clock edge ===//
//
// A concurrent assertion lowers to a process that waits for its clock edge
// and resumes in the Observed region, where its property expression is
// evaluated on sampled values (IEEE 1800-2023 4.4.2.5, 16.5.1). Pass/fail
// code runs in spawned processes. A design with many assertions on one clock
// otherwise pays a scheduler resumption per assertion and edge.
//
// Processes that wait for the same edge and resume in the Observed region
// become one process. It runs every member's start-up code
// in turn, waits once, and then runs each member's activation in turn. Every
// member is waiting whenever the fused process waits, because each activation
// ends at its member's single wait. So one edge resumes all members, as it
// did before. Running them back to back is one ordering of their events
// (4.7). A member's loop-carried values flow through an exit block of its
// own, which dominates every later member's code and the shared wait.
//
// Members must not depend on their process identity, directly or through
// the functions they call: no process handle, block activation, disable,
// monitor, or independent return. A return guarded by design-wide
// termination ends the shared activation. Nor may they, or code they call or
// spawn, use random state: each process has its own random number generator and
// seeds the processes it creates from it (18.14.1), so merged members would
// share one stream. Operations with unknown effects are treated as using
// both. Members write only private state, so none can change the clock that
// the shared wait observes. The root must spawn each member exactly once and
// drop the handle. Requires VPI off, since a VPI client can distinguish the
// processes.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "talos/Analysis/ActivationPhaseAnalysis.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/ScopeExit.h"
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

// A positive delay must precede every execution of the sole clock store.
// Thus every Active port copy settles before Observed, even if several
// levels separate it from the writer (IEEE 1800-2023 4.5, 9.4.1, 23.3.3).
bool isDelayedClockWriter(sim::SimFuncOp function, uint64_t clock,
                          const analysis::ActivationPhaseAnalysis &phases) {
  if (!function || function.getHomeRegion() != sim::EventRegion::Active ||
      function.getDomain() != sim::ExecutionDomain::Design)
    return false;
  sim::SimRefStoreOp store;
  for (Block &block : function.getBody())
    for (Operation &op : block) {
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op)) {
        if (store || phases.getRoot(function, write.getReference()) != clock)
          return false;
        store = write;
      } else if (!isa<sim::SimRefLoadOp, sim::SimSuspendDelayOp>(op) &&
                 !isMemoryEffectFree(&op))
        return false;
    }
  Block *before = store ? store->getBlock()->getSinglePredecessor() : nullptr;
  auto delay = before
                   ? dyn_cast<sim::SimSuspendDelayOp>(before->getTerminator())
                   : sim::SimSuspendDelayOp{};
  auto amount = delay ? delay.getDelay().getDefiningOp<sim::SimTimeConstantOp>()
                      : sim::SimTimeConstantOp{};
  return amount && amount.getValue() > 0 &&
         delay.getResumeRegion().value_or(sim::EventRegion::Active) ==
             sim::EventRegion::Active;
}

bool isTerminationExit(Block *block) {
  return !block->hasNoPredecessors() && block->getOperations().size() == 1 &&
         llvm::all_of(block->getPredecessors(), [&](Block *pred) {
           auto branch = dyn_cast<cf::CondBranchOp>(pred->getTerminator());
           return branch && branch.getTrueDest() == block &&
                  branch.getFalseDest() != block &&
                  branch.getCondition()
                      .getDefiningOp<sim::SimTerminationRequestedOp>();
         });
}

// The root initializer and its ordinary, zero-time callees may only put 0
// on this bit. Copies initially contain X (or 0 for bit), so propagation at
// startup cannot produce a posedge (6.8, Table 6-7, Table 9-2).
bool hasOnlyLowInitialWrites(sim::SimFuncOp function, uint64_t clock,
                             const analysis::ActivationPhaseAnalysis &phases,
                             SymbolTable &symbols,
                             DenseSet<Operation *> &visiting) {
  if (!function || function.isExternal() || !visiting.insert(function).second)
    return false;
  llvm::scope_exit guard([&] { visiting.erase(function); });
  for (Block &block : function.getBody()) {
    if (ArrayAttr effects = phases.getFragmentEffects(&block)) {
      bool mayWrite = llvm::any_of(
          effects.getAsRange<schedule::ComputeEffectAttr>(), [&](auto effect) {
            using Kind = schedule::ComputeEffectKind;
            if ((effect.getEffect() != Kind::Write &&
                 effect.getEffect() != Kind::NBA &&
                 effect.getEffect() != Kind::Drive) ||
                effect.getTarget() == schedule::ComputeTargetKind::Local)
              return false;
            auto roots =
                phases.getEffectRoots(function.getSymNameAttr(), effect);
            return !roots || llvm::is_contained(*roots, clock);
          });
      if (!mayWrite)
        continue;
    }
    for (Operation &op : block) {
      if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
        auto target = phases.getRoot(function, store.getReference());
        if (!target)
          return false;
        if (*target != clock)
          continue;
        Value value = store.getValue();
        if (auto level = value.getDefiningOp<sim::SimLogicConstantOp>()) {
          if (level.getValue().getBitWidth() != 1 ||
              !level.getValue().isZero() || !level.getUnknown().isZero())
            return false;
        } else if (!value.getType().isInteger(1) ||
                   !matchPattern(value, m_Zero()))
          return false;
      } else if (auto call = dyn_cast<sim::SimCallOp>(op)) {
        if (!hasOnlyLowInitialWrites(
                symbols.lookup<sim::SimFuncOp>(call.getCallee()), clock, phases,
                symbols, visiting))
          return false;
      } else if (!isa<sim::SimSpawnOp>(op)) {
        // The spawned processes have their own entries in the writer graph.
        auto effects = getEffectsRecursively(&op);
        if (!effects || llvm::any_of(*effects, [](const auto &effect) {
              return isa<MemoryEffects::Write>(effect.getEffect()) &&
                     isa<sim::StorageResource, sim::ExternalResource>(
                         effect.getResource());
            }))
          return false;
      }
    }
  }
  return true;
}

// Keys for Observed posedge waits only. Active readers and clock storage keep
// their individual updates. A missing writer, initializer or copy proof keeps
// the original wait.
DenseMap<uint64_t, uint64_t> observedPosedgeOrigins(
    sim::SimDesignOp design, sim::SimFuncOp root, SymbolTable &symbols,
    const analysis::HandleDataflowAnalysis &handles, ArrayRef<uint64_t> watched,
    function_ref<bool(StringAttr)> startsOnce) {
  analysis::ActivationPhaseAnalysis phases(design, handles);
  DenseMap<uint64_t, uint64_t> origins;
  if (!phases.isValid() || phases.getClockCopies().empty())
    return origins;
  DenseMap<uint64_t, SmallVector<uint64_t>> descendants;
  for (uint64_t clock : watched) {
    uint64_t origin = clock;
    DenseSet<uint64_t> seen;
    while (true) {
      auto copy = phases.getClockCopies().find(origin);
      if (copy == phases.getClockCopies().end())
        break;
      auto process = symbols.lookup<sim::SimFuncOp>(copy->second.process);
      if (!seen.insert(origin).second || !startsOnce(copy->second.process) ||
          process.getHomeRegion() != sim::EventRegion::Active ||
          process.getDomain() != sim::ExecutionDomain::Design ||
          cast<sim::SimSuspendChangeOp>(
              process.getBody().back().getTerminator())
                  .getResumeRegion()
                  .value_or(sim::EventRegion::Active) !=
              sim::EventRegion::Active) {
        origin = clock;
        break;
      }
      origin = copy->second.source;
    }
    descendants[origin].push_back(clock);
  }
  DenseMap<uint64_t, sim::SimFuncOp> writers;
  DenseSet<uint64_t> initialized;
  for (auto &[block, info] : phases.getBlockInfos()) {
    auto function = cast<sim::SimFuncOp>(block->getParentOp());
    if (function.getEntryKind() == sim::EntryKind::Function)
      continue;
    for (auto [clock, update] : info.writes) {
      if (clock == analysis::ActivationPhaseAnalysis::anyRoot)
        return origins;
      if (!descendants.count(clock))
        continue;
      if (function == root) {
        initialized.insert(clock);
        continue;
      }
      auto [writer, inserted] = writers.try_emplace(clock, function);
      if (writer->second != function ||
          update != analysis::ActivationPhaseAnalysis::BlockInfo::Update::Same)
        writer->second = {};
    }
  }
  for (auto &[clock, copies] : descendants) {
    sim::SimFuncOp writer = writers.lookup(clock);
    if (copies.size() < 2 || !writer || !startsOnce(writer.getSymNameAttr()) ||
        !isDelayedClockWriter(writer, clock, phases))
      continue;
    DenseSet<Operation *> visiting;
    if (initialized.contains(clock) &&
        !hasOnlyLowInitialWrites(root, clock, phases, symbols, visiting))
      continue;
    for (uint64_t copy : copies)
      origins[copy] = clock;
  }
  return origins;
}

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
        // A true design-wide finish poll also ends every remaining ordinary
        // Observed activation (1800-2023 20.2, 20.10). Clone this branch and
        // its return intact. An independent member return cannot end peers.
        traits.processDependent |=
            top && !isTerminationExit(operation->getBlock());
        return;
      }
      if (top && isa<sim::SimSampledHistoryOp>(operation)) {
        // Its only process-local state is a ring keyed by (process, site).
        // Each $past expression keeps its own history of gated clock ticks
        // (IEEE 1800-2023 16.9.3).
        return;
      }
      StringRef name = operation->getName().getStringRef();
      if (name.starts_with("simulation.monitor.") ||
          name.starts_with("simulation.coverage"))
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
  // Group by the waited root and edge, and by everything else that the
  // fused process takes from its first member.
  using Key =
      std::tuple<uint64_t, unsigned, unsigned, unsigned, unsigned, Attribute>;
  llvm::MapVector<Key, SmallVector<Member>> groups;
  llvm::SmallSetVector<uint64_t, 8> risingClocks;
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
    if (member.suspend.getEdge() == sim::EdgeKind::Posedge &&
        fact->second.resource == schedule::ComputeResourceKind::Storage &&
        fact->second.width == 1)
      risingClocks.insert(*watched);
    groups[key].push_back(std::move(member));
  }

  if (risingClocks.size() > 1 && design.getComputeGraphAttr() && module &&
      !sim::has<sim::metadata::SnapshotPublications>(module)) {
    auto startsOnce = [&](StringAttr name) {
      auto it = spawns.find(name);
      return it != spawns.end() && it->second.size() == 1 &&
             it->second.front()->getBlock() == &root.getBody().front() &&
             it->second.front().getResult().use_empty() &&
             symbolUses.lookup(name) == 1;
    };
    auto origins =
        observedPosedgeOrigins(design, root, symbols, provenance,
                               risingClocks.getArrayRef(), startsOnce);
    if (!origins.empty()) {
      decltype(groups) merged;
      for (auto &[key, members] : groups) {
        Key canonical = key;
        if (std::get<1>(key) == static_cast<unsigned>(sim::EdgeKind::Posedge))
          if (auto origin = origins.find(std::get<0>(key));
              origin != origins.end())
            std::get<0>(canonical) = origin->second;
        llvm::append_range(
            merged[canonical],
            llvm::make_range(std::make_move_iterator(members.begin()),
                             std::make_move_iterator(members.end())));
      }
      groups = std::move(merged);
    }
  }

  uint64_t nextStorage = 0;
  for (auto storage : design.getOps<sim::SimStorageDeclOp>())
    nextStorage = std::max<uint64_t>(nextStorage, storage.getId() + 1);
  DenseMap<uint64_t, uint64_t> scopes;
  for (auto declaration : design.getOps<sim::SimCodeUnitDeclOp>())
    scopes.try_emplace(declaration.getId(), declaration.getScopeId());
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
    DenseMap<std::pair<Operation *, uint64_t>, uint64_t> historySites;
    auto cloneOperations = [&](ArrayRef<Block *> sources, IRMapping &mapping) {
      for (Block *source : sources) {
        builder.setInsertionPointToEnd(mapping.lookup(source));
        for (Operation &operation : *source) {
          if (auto history = dyn_cast<sim::SimSampledHistoryOp>(operation)) {
            // The original token separated equal site IDs in different
            // members. Repeated visits to one member's site still share its
            // ring, including visits from both startup and activation.
            auto site = historySites.try_emplace(
                {source->getParentOp(), history.getId()},
                historySites.size() + 1);
            cast<sim::SimSampledHistoryOp>(builder.clone(operation, mapping))
                .setId(site.first->second);
            continue;
          }
          auto allocation = dyn_cast<sim::SimRefAllocOp>(operation);
          if (!source->isEntryBlock() || !allocation ||
              !isa<IntegerType>(allocation.getInitialValue().getType()) ||
              !llvm::any_of(
                  allocation.getResult().getUsers(), [&](Operation *user) {
                    auto spawn = dyn_cast<sim::SimSpawnOp>(user);
                    auto actor =
                        spawn
                            ? symbols.lookup<sim::SimFuncOp>(spawn.getCallee())
                            : sim::SimFuncOp{};
                    return actor &&
                           schedule::has<schedule::Field::ConcurrentCancel>(
                               actor) &&
                           schedule::has<schedule::Field::DetachedControls>(
                               actor);
                  })) {
            builder.clone(operation, mapping);
            continue;
          }
          // This member is spawned once at the root; its entry runs once.
          // The monitor and its detached cancellation actors share this one
          // private cell for the entire simulation (1800-2023 9.3.2, 16.12).
          // Keep the initialization at the original point in the start-up CFG.
          Location loc = allocation.getLoc();
          auto parent = allocation->getParentOfType<sim::SimFuncOp>();
          auto unit = parent.getCodeUnitIdAttr();
          auto scope = unit ? scopes.find(unit.getUInt()) : scopes.end();
          if (scope == scopes.end()) {
            builder.clone(operation, mapping);
            continue;
          }
          uint64_t id = nextStorage++;
          {
            OpBuilder::InsertionGuard guard(builder);
            builder.setInsertionPoint(kernel);
            sim::SimStorageDeclOp::create(
                builder, loc, id, scope->second,
                allocation.getInitialValue().getType(), sim::Lifetime::Design,
                StringAttr{}, StringAttr{},
                schedule::ComputeObservabilityKindAttr::get(
                    design.getContext(),
                    schedule::ComputeObservabilityKind::Invisible),
                sim::VPITypeSemanticsAttr{});
          }
          Value reference = sim::SimContextStorageOp::create(
              builder, loc, allocation.getType(),
              mapping.lookup(source->getArgument(0)),
              builder.getI64IntegerAttr(id));
          sim::SimRefStoreOp::create(
              builder, loc,
              mapping.lookupOrDefault(allocation.getInitialValue()), reference);
          mapping.map(allocation.getResult(), reference);
        }
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
