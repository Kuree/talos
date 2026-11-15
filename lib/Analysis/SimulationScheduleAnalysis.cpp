//===- SimulationScheduleAnalysis.cpp - Shared schedule ranks ------------===//

#include "talos/Analysis/SimulationScheduleAnalysis.h"
#include "talos/Analysis/ActivationControlFlow.h"
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"

#include <limits>
#include <map>
#include <set>

using namespace mlir;

namespace talos::analysis {
namespace {

bool isObserverCaptureBridge(Block &block) {
  if (block.getOperations().size() != 1)
    return false;
  auto branch = dyn_cast<cf::BranchOp>(block.getTerminator());
  return branch && ::talos::schedule::has<
                       ::talos::schedule::Field::ObserverCaptureBridge>(branch);
}

bool isScheduledRegion(schedule::ComputeRegionKind kind) {
  return kind == schedule::ComputeRegionKind::Active ||
         kind == schedule::ComputeRegionKind::Observed ||
         kind == schedule::ComputeRegionKind::Reactive ||
         kind == schedule::ComputeRegionKind::Postponed;
}

// Input settling is a publication-value property, not an owner-graph property.
// A FIFO's return-data publication can be independent of pop even though the
// same activation consumes pop while computing its next pointer. Collapsing
// those outputs into one owner invents feedback and misses this prerequisite.
// All facts refer to this immutable revision; activation views are canonical
// disposable copies, and only their range facts survive in the cache.
class PreemptionInputAnalysis {
public:
  PreemptionInputAnalysis(sim::SimDesignOp design,
                          schedule::ComputeGraphAttr graph,
                          const llvm::StringMap<sim::SimFuncOp> &functions,
                          const DenseSet<Operation *> &interrupted)
      : handles(design), controlActivations(design), interrupted(interrupted) {
    for (auto function : design.getBody().getOps<sim::SimFuncOp>())
      if (isSettlingEntryKind(function.getEntryKind()) &&
          function.getHomeRegion() == sim::EventRegion::Active) {
        ids[function] = actors.size();
        actors.push_back(function);
      }
    DenseMap<Operation *, DenseSet<Block *>> prefixes;
    for (auto function : actors) {
      if (!interrupted.contains(function) || function.getBody().empty())
        continue;
      SmallVector<Block *> pending{&function.getBody().front()};
      function.walk([&](Operation *op) {
        if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(op))
          pending.push_back(op->getSuccessor(0));
      });
      auto &blocks = prefixes[function];
      while (!pending.empty()) {
        Block *block = pending.pop_back_val();
        if (!blocks.insert(block).second ||
            sim::isSuspensionOp(block->getTerminator()))
          continue;
        pending.append(block->succ_begin(), block->succ_end());
      }
    }
    ComputeGraphBlockIndex blockIndex;
    for (Attribute raw : graph.getNodes()) {
      auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
      if (!fragment)
        continue;
      auto function = functions.lookup(fragment.getFunction().getValue());
      auto actor = ids.find(function);
      if (actor == ids.end())
        continue;
      auto prefix = prefixes.find(function);
      bool prefixBlock = prefix != prefixes.end() &&
                         prefix->second.contains(
                             blockIndex.lookup(function, fragment.getBlock()));
      for (Attribute rawEffect : fragment.getEffects()) {
        auto effect = cast<schedule::ComputeEffectAttr>(rawEffect);
        bool read = effect.getEffect() == schedule::ComputeEffectKind::Read;
        if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
            effect.getDeferred() || !effect.getWidth()) {
          if (read && !effect.getDeferred())
            unresolvedReads.insert(actor->second);
          continue;
        }
        auto root = ActivationMemoryAnalysis::getRoot(effect.getResource(),
                                                      effect.getDescriptor());
        if (!root) {
          if (read)
            unresolvedReads.insert(actor->second);
          continue;
        }
        Range range{*root, effect.getLow(), effect.getWidth()};
        if (read)
          actorReads[actor->second].push_back(range);
        // A continuous driver publishes its net exactly like a variable
        // write; both can feed an input read before the first handoff.
        if (effect.getEffect() == schedule::ComputeEffectKind::Write ||
            effect.getEffect() == schedule::ComputeEffectKind::Drive)
          sources[range.root].push_back({actor->second, range});
        else if (prefixBlock &&
                 effect.getEffect() == schedule::ComputeEffectKind::Read)
          prefixReads[function].push_back(range);
      }
    }
    for (auto &[function, ranges] : prefixReads)
      normalize(ranges);
    for (auto &[actor, ranges] : actorReads)
      normalize(ranges);
    for (auto &[root, writers] : sources) {
      llvm::sort(writers, [](const Source &a, const Source &b) {
        return std::tie(a.range.low, a.range.width, a.actor) <
               std::tie(b.range.low, b.range.width, b.actor);
      });
      writers.erase(std::unique(writers.begin(), writers.end(),
                                [](const Source &a, const Source &b) {
                                  return a.actor == b.actor &&
                                         a.range == b.range;
                                }),
                    writers.end());
    }
  }

  /// Independent producers of inputs read before the first handoff must
  /// settle before it. `dependents` receives the producers whose cones read
  /// the interrupted actor's or a peer's publications: they must run only
  /// after its final phase, never on partial state inside the handoff window
  /// (9.4.2). `proved` becomes false when a cone is unknown.
  /// `after` receives (interrupted actor, producer) pairs: a producer whose
  /// cone reads another interrupted actor runs after that actor's final
  /// phase, so it never publishes from that actor's partial state.
  SmallVector<sim::SimFuncOp>
  getPrerequisites(sim::SimFuncOp function, ArrayRef<sim::SimFuncOp> peers,
                   bool &proved, SmallVectorImpl<sim::SimFuncOp> &dependents,
                   SmallVectorImpl<std::pair<sim::SimFuncOp, sim::SimFuncOp>>
                       &after,
                   SmallVectorImpl<sim::SimFuncOp> &afterAll) {
    consumer = function;
    peerActors.clear();
    for (auto peer : peers)
      peerActors.insert(peer);
    queries.clear();
    work = 0;
    std::set<unsigned> prerequisites, dependentIds;
    for (const Range &range : prefixReads[function]) {
      const Query &query = prove(range, 0);
      if (query.state == State::Unsupported || query.state == State::Visiting) {
        proved = false;
        continue;
      }
      prerequisites.insert(query.producers.begin(), query.producers.end());
      dependentIds.insert(query.dependents.begin(), query.dependents.end());
      orderAfter.insert(query.after.begin(), query.after.end());
    }
    for (auto [source, producer] : orderAfter)
      if (!dependentIds.count(producer))
        after.push_back({actors[source], actors[producer]});
    orderAfter.clear();
    for (unsigned producer : cyclicProducers)
      afterAll.push_back(actors[producer]);
    cyclicProducers.clear();
    SmallVector<sim::SimFuncOp> result;
    for (unsigned id : prerequisites)
      if (!dependentIds.count(id))
        result.push_back(actors[id]);
    for (unsigned id : dependentIds)
      dependents.push_back(actors[id]);
    return result;
  }

private:
  enum class State { Visiting, Unsupported, Independent, Dependent };
  struct Query {
    State state = State::Visiting;
    SmallVector<unsigned> producers, dependents;
    /// Interrupted actors reached by this cone, and the (actor, producer)
    /// pairs ordering each producer after such an actor.
    SmallVector<unsigned> sources;
    SmallVector<std::pair<unsigned, unsigned>> after;
    /// The cone closes a producer cycle; its classification is incomplete.
    bool cyclic = false;
  };
  struct Source {
    unsigned actor;
    Range range;
  };
  struct Publication {
    Ranges reads, writes;
  };
  // Direct prefix reads may skip peer writes; transitive producer inputs may
  // not. The two answers for one range differ, so the depth class is keyed.
  using Key = std::tuple<uint64_t, uint64_t, uint64_t, bool>;

  const SmallVector<Publication> *getPublications(unsigned actor) {
    auto [found, inserted] = publications.try_emplace(actor);
    if (!inserted)
      return found->second ? &*found->second : nullptr;
    auto function = actors[actor];
    unsigned operations = 0;
    function.walk([&](Operation *) {
      return ++operations > 4096 ? WalkResult::interrupt()
                                 : WalkResult::advance();
    });
    if (operations > 4096 || operations > operationBudget)
      return nullptr;
    operationBudget -= operations;
    ActivationPreparationOptions preparation;
    preparation.controls = &controlActivations;
    ActivationRegionAnalysis activation(
        prepareActivation(function, preparation), handles,
        ActivationMemoryAnalysis::DependencyMode::ReachingValues);
    auto facts = getActivationPublications(activation);
    if (!facts)
      return nullptr;
    // Recursive queries can grow this DenseMap, so never retain its iterator.
    SmallVector<Publication> ranges;
    for (auto &publication : *facts)
      ranges.push_back(
          {std::move(publication.reads), std::move(publication.writes)});
    publications[actor] = std::move(ranges);
    return &*publications.find(actor)->second;
  }

  const Query &prove(Range range, unsigned depth) {
    auto [entry, inserted] = queries.try_emplace(
        Key{range.root, range.low, range.width, depth == 0});
    Query &query = entry->second;
    if (!inserted)
      return query;
    if (depth > 128 || ++work > 4096) {
      query.state = State::Unsupported;
      return query;
    }
    auto found = sources.find(range.root);
    SmallVector<unsigned> writers;
    if (found != sources.end())
      for (const Source &source : found->second) {
        if (source.range.low >= range.low + range.width)
          break;
        if (++work > 4096) {
          query.state = State::Unsupported;
          return query;
        }
        if (range.low < source.range.low + source.range.width)
          writers.push_back(source.actor);
      }
    llvm::sort(writers);
    writers.erase(std::unique(writers.begin(), writers.end()), writers.end());
    std::set<unsigned> prerequisites, dependents, sources;
    std::set<std::pair<unsigned, unsigned>> after;
    bool dependent = false, cyclic = false;
    for (unsigned writer : writers) {
      // The cohort's source order deliberately chooses which publication is
      // captured. In particular an early snapshot may precede this peer's
      // body; only independent producers outside that order are prerequisites.
      // A producer deriving its output from a peer or from the interrupted
      // actor itself cannot settle before the prefix; it is ordered after the
      // actor's final phase instead (9.4.2).
      if (peerActors.contains(actors[writer])) {
        dependent |= depth != 0;
        continue;
      }
      if (actors[writer] == consumer) {
        dependent = true;
        continue;
      }
      if (interrupted.contains(actors[writer])) {
        sources.insert(writer);
        continue;
      }
      // Copy only the demanded output's input ranges before recursion: a new
      // lazy producer query can reallocate the publication cache.
      Ranges inputs;
      bool publishes = false;
      if (const auto *facts = getPublications(writer)) {
        for (const Publication &publication : *facts)
          if (llvm::any_of(publication.writes, [&](const Range &write) {
                return write.root == range.root &&
                       write.low < range.low + range.width &&
                       range.low < write.low + write.width;
              })) {
            publishes = true;
            unite(inputs, publication.reads);
          }
      } else {
        // Without per-publication facts, every read of the producer may feed
        // this output. That over-approximates its cone; an unresolved read
        // leaves the cone unknown.
        if (unresolvedReads.contains(writer)) {
          query.state = State::Unsupported;
          return query;
        }
        publishes = true;
        inputs = actorReads.lookup(writer);
      }
      if (!publishes)
        continue;
      bool writerDependent = false;
      std::set<unsigned> writerSources;
      for (const Range &input : inputs) {
        const Query &dependency = prove(input, depth + 1);
        if (dependency.state == State::Unsupported) {
          query.state = State::Unsupported;
          return query;
        }
        // A producer cycle cannot be classified from a partial answer. Order
        // its producers after every interrupted actor instead: a later run is
        // always sound, since the reader is armed again by then.
        bool closesCycle =
            dependency.state == State::Visiting || dependency.cyclic;
        writerDependent |=
            dependency.state == State::Dependent || closesCycle;
        cyclic |= closesCycle;
        prerequisites.insert(dependency.producers.begin(),
                             dependency.producers.end());
        dependents.insert(dependency.dependents.begin(),
                          dependency.dependents.end());
        writerSources.insert(dependency.sources.begin(),
                             dependency.sources.end());
        after.insert(dependency.after.begin(), dependency.after.end());
      }
      (writerDependent ? dependents : prerequisites).insert(writer);
      if (cyclic)
        cyclicProducers.insert(writer);
      dependent |= writerDependent;
      for (unsigned source : writerSources)
        after.insert({source, writer});
      sources.insert(writerSources.begin(), writerSources.end());
    }
    query.producers.assign(prerequisites.begin(), prerequisites.end());
    query.dependents.assign(dependents.begin(), dependents.end());
    query.sources.assign(sources.begin(), sources.end());
    query.after.assign(after.begin(), after.end());
    query.cyclic = cyclic;
    query.state = dependent ? State::Dependent : State::Independent;
    return query;
  }

  HandleDataflowAnalysis handles;
  ControlActivationAnalysis controlActivations;
  const DenseSet<Operation *> &interrupted;
  DenseSet<Operation *> peerActors;
  SmallVector<sim::SimFuncOp> actors;
  DenseMap<Operation *, unsigned> ids;
  DenseMap<uint64_t, SmallVector<Source>> sources;
  DenseMap<Operation *, Ranges> prefixReads;
  std::set<std::pair<unsigned, unsigned>> orderAfter;
  std::set<unsigned> cyclicProducers;
  DenseMap<unsigned, Ranges> actorReads;
  DenseSet<unsigned> unresolvedReads;
  DenseMap<unsigned, std::optional<SmallVector<Publication>>> publications;
  std::map<Key, Query> queries;
  sim::SimFuncOp consumer;
  unsigned work = 0;
  unsigned operationBudget = 65536;
};

} // namespace

bool isSettlingEntryKind(sim::EntryKind kind) {
  return kind == sim::EntryKind::AlwaysComb ||
         kind == sim::EntryKind::AlwaysLatch ||
         kind == sim::EntryKind::Continuous ||
         kind == sim::EntryKind::PortInput ||
         kind == sim::EntryKind::PortOutput;
}

SmallVector<StartupPhase> collectStartupPhases(
    sim::SimDesignOp design,
    llvm::function_ref<std::optional<uint32_t>(sim::SimFuncOp)> entryID) {
  llvm::StringMap<sim::SimFuncOp> functions;
  for (auto function : design.getBody().getOps<sim::SimFuncOp>())
    functions[function.getSymName()] = function;
  SmallVector<StartupPhase> phases;
  for (auto root : design.getBody().getOps<sim::SimFuncOp>()) {
    if (root.getEntryKind() != sim::EntryKind::RootInitializer)
      continue;
    for (Block &block : root.getBody()) {
      // Cross-region dependencies are enforced by the event loop. Separate
      // barriers also keep distinct root blocks from acquiring new ordering.
      std::map<sim::EventRegion, StartupPhase> byRegion;
      for (auto spawn : block.getOps<sim::SimSpawnOp>()) {
        auto target = functions.lookup(spawn.getCallee());
        if (!target || target.getBody().empty())
          continue;
        auto id = entryID(target);
        if (!id)
          continue;
        if (sim::isStartupEntryKind(target.getEntryKind()) &&
            !schedule::has<sim::startupWithoutSuspensionAttrName>(target))
          byRegion[target.getHomeRegion()].startups.push_back(*id);
        else if (target.getEntryKind() == sim::EntryKind::Initial)
          byRegion[target.getHomeRegion()].initials.push_back(*id);
      }
      for (auto &[region, phase] : byRegion) {
        if (phase.startups.empty() || phase.initials.empty())
          continue;
        for (auto *ids : {&phase.startups, &phase.initials}) {
          llvm::sort(*ids);
          ids->erase(std::unique(ids->begin(), ids->end()), ids->end());
        }
        phases.push_back(std::move(phase));
      }
    }
  }
  return phases;
}

SmallVector<schedule::ComputeEdgeAttr> projectActivationSchedulingEdges(
    ArrayRef<schedule::ComputeEdgeAttr> edges,
    llvm::function_ref<bool(uint32_t)> isSettlingSource) {
  // A sensitivity edge ends at the wait; execution starts at its resume
  // continuation. Project the publication, not the wait's repeating backedge.
  // This is shared with graph construction so rank refinement cannot omit
  // boundary consumers or invent a different activation graph.
  SmallVector<schedule::ComputeEdgeAttr> projected(edges.begin(), edges.end());
  DenseMap<uint32_t, SmallVector<uint32_t>> continuations;
  for (auto edge : edges)
    if (edge.getKind() == schedule::ComputeEdgeKind::Resume)
      continuations[edge.getSource()].push_back(edge.getTarget());
  for (auto edge : edges) {
    if (edge.getKind() != schedule::ComputeEdgeKind::Sensitivity ||
        !isSettlingSource(edge.getSource()))
      continue;
    for (uint32_t continuation : continuations[edge.getTarget()])
      projected.push_back(schedule::ComputeEdgeAttr::get(
          edge.getContext(), edge.getSource(), continuation,
          schedule::ComputeEdgeKind::Sensitivity, edge.getResource()));
  }
  return projected;
}

Block *lookupComputeGraphBlock(sim::SimFuncOp function, uint32_t ordinal) {
  for (Block &block : function.getBody()) {
    if (isObserverCaptureBridge(block))
      continue;
    if (ordinal-- == 0)
      return &block;
  }
  return nullptr;
}

Block *ComputeGraphBlockIndex::lookup(sim::SimFuncOp function,
                                      uint32_t ordinal) {
  auto [found, inserted] = blocks.try_emplace(function.getOperation());
  if (inserted)
    for (Block &block : function.getBody())
      if (!isObserverCaptureBridge(block))
        found->second.push_back(&block);
  return ordinal < found->second.size() ? found->second[ordinal] : nullptr;
}

FailureOr<SimulationScheduleAnalysis>
SimulationScheduleAnalysis::compute(ModuleOp module) {
  sim::SimDesignOp design;
  module.walk([&](sim::SimDesignOp candidate) { design = candidate; });
  if (!design)
    return SimulationScheduleAnalysis{};
  return compute(design);
}

FailureOr<SimulationScheduleAnalysis>
SimulationScheduleAnalysis::compute(sim::SimDesignOp design) {
  SimulationScheduleAnalysis result;
  llvm::StringMap<sim::SimFuncOp> functions;
  llvm::DenseMap<Operation *, SmallVector<Block *>> graphBlocks;
  uint32_t fallback = 0;
  for (sim::SimFuncOp function : design.getBody().getOps<sim::SimFuncOp>()) {
    functions[function.getSymName()] = function;
    SmallVector<Block *> &blocks = graphBlocks[function.getOperation()];
    blocks.reserve(function.getBody().getBlocks().size());
    for (Block &block : function.getBody())
      if (!isObserverCaptureBridge(block))
        blocks.push_back(&block);
    if (function.getEntryKind() == sim::EntryKind::Function ||
        function.getEntryKind() == sim::EntryKind::Observer)
      continue;
    result.entryRanks[function.getOperation()] = fallback;
    for (Block &block : function.getBody())
      result.blockRanks[&block] = fallback;
    if (fallback != std::numeric_limits<uint32_t>::max())
      ++fallback;
  }

  schedule::ComputeGraphAttr graph = design.getComputeGraphAttr();
  if (!graph)
    return result;
  ArrayAttr nodes = graph.getNodes();
  // Refine convergence ties using the complete activation graph, including
  // boundary actors. Helper-only dependencies cannot define global priority.
  // Region/group order, procedural control loops and ownership stay intact.
  SmallVector<uint32_t> groupOf, position;
  uint32_t nextGroup = 0;
  auto refine = [](schedule::ComputeGroupAttr group) {
    return group.getSchedule() == schedule::ComputeScheduleKind::Convergence &&
           group.getFragments().size() > 1;
  };
  for (Attribute rawRegion : graph.getRegions()) {
    auto region = cast<schedule::ComputeRegionAttr>(rawRegion);
    if (!isScheduledRegion(region.getKind()))
      continue;
    for (Attribute rawGroup : region.getGroups()) {
      auto group = cast<schedule::ComputeGroupAttr>(rawGroup);
      if (!refine(group))
        continue;
      if (groupOf.empty())
        groupOf.assign(nodes.size(), UINT32_MAX);
      for (int64_t member : group.getFragments().asArrayRef())
        groupOf[member] = nextGroup;
      ++nextGroup;
    }
  }
  if (nextGroup) {
    SmallVector<schedule::ComputeEdgeAttr> graphEdges;
    for (Attribute raw : graph.getEdges())
      graphEdges.push_back(cast<schedule::ComputeEdgeAttr>(raw));
    auto projected =
        projectActivationSchedulingEdges(graphEdges, [&](uint32_t source) {
          auto fragment =
              dyn_cast<schedule::ComputeFragmentAttr>(nodes[source]);
          auto function =
              fragment ? functions.lookup(fragment.getFunction().getValue())
                       : sim::SimFuncOp{};
          return function && isSettlingEntryKind(function.getEntryKind());
        });
    std::vector<std::pair<uint32_t, uint32_t>> edges;
    for (auto edge : projected)
      if (edge.getKind() != schedule::ComputeEdgeKind::Resume &&
          edge.getKind() != schedule::ComputeEdgeKind::Spawn &&
          groupOf[edge.getSource()] != UINT32_MAX &&
          groupOf[edge.getSource()] == groupOf[edge.getTarget()])
        edges.emplace_back(edge.getSource(), edge.getTarget());
    llvm::StringMap<uint32_t> entries;
    for (Attribute raw : nodes)
      if (auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
          fragment && fragment.getBlock() == 0)
        entries[fragment.getFunction().getValue()] = fragment.getId();
    auto phases = collectStartupPhases(
        design, [&](sim::SimFuncOp function) -> std::optional<uint32_t> {
          auto found = entries.find(function.getSymName());
          return found == entries.end() ? std::nullopt
                                        : std::optional(found->second);
        });
    SmallVector<StartupPhase> groupedPhases;
    for (const auto &phase : phases) {
      std::map<uint32_t, StartupPhase> byGroup;
      for (uint32_t id : phase.startups)
        if (groupOf[id] != UINT32_MAX)
          byGroup[groupOf[id]].startups.push_back(id);
      for (uint32_t id : phase.initials)
        if (groupOf[id] != UINT32_MAX)
          byGroup[groupOf[id]].initials.push_back(id);
      for (const auto &[group, members] : byGroup) {
        if (members.startups.empty() || members.initials.empty())
          continue;
        groupedPhases.push_back(members);
      }
    }
    // Each refined group is already an activation SCC. ActivationOrder's
    // within-SCC tie-break is reverse DFS finish order with sorted successors.
    // Traverse the SAME logical successors here without expanding the phase
    // product. A shared cursor skips targets already discovered by any source;
    // skipped edges cannot affect DFS finish order. A virtual barrier's DFS
    // order would instead move some initial entries ahead of startup entries.
    SmallVector<SmallVector<uint32_t>> successors(nodes.size());
    for (auto [source, target] : edges)
      successors[source].push_back(target);
    for (auto &targets : successors) {
      llvm::sort(targets);
      targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
    }
    SmallVector<SmallVector<unsigned>> phasesForSource(nodes.size());
    for (auto [index, phase] : llvm::enumerate(groupedPhases))
      for (uint32_t source : phase.startups)
        phasesForSource[source].push_back(index);
    SmallVector<size_t> phaseCursor(groupedPhases.size(), 0);
    SmallVector<bool> seen(nodes.size(), false);
    SmallVector<std::pair<uint32_t, size_t>> walk;
    position.resize(nodes.size());
    uint32_t remaining = nodes.size();
    for (uint32_t root = 0; root < nodes.size(); ++root) {
      if (seen[root])
        continue;
      seen[root] = true;
      walk.emplace_back(root, 0);
      while (!walk.empty()) {
        auto &[node, cursor] = walk.back();
        auto &targets = successors[node];
        while (cursor < targets.size() && seen[targets[cursor]])
          ++cursor;
        uint32_t next = cursor < targets.size() ? targets[cursor] : UINT32_MAX;
        for (unsigned phase : phasesForSource[node]) {
          auto &initials = groupedPhases[phase].initials;
          auto &index = phaseCursor[phase];
          while (index < initials.size() && seen[initials[index]])
            ++index;
          if (index < initials.size())
            next = std::min(next, initials[index]);
        }
        if (next == UINT32_MAX) {
          position[node] = --remaining;
          walk.pop_back();
        } else {
          seen[next] = true;
          walk.emplace_back(next, 0);
        }
      }
    }
  }
  uint32_t rank = 0;
  for (Attribute regionAttribute : graph.getRegions()) {
    auto region = dyn_cast<schedule::ComputeRegionAttr>(regionAttribute);
    if (!region || !isScheduledRegion(region.getKind()))
      continue;
    for (Attribute groupAttribute : region.getGroups()) {
      auto group = dyn_cast<schedule::ComputeGroupAttr>(groupAttribute);
      if (!group)
        continue;
      ArrayRef<int64_t> members = group.getFragments().asArrayRef();
      SmallVector<int64_t> ordered;
      bool refined = refine(group);
      if (refined) {
        ordered.assign(members.begin(), members.end());
        llvm::sort(ordered, [&](int64_t lhs, int64_t rhs) {
          return position[lhs] < position[rhs];
        });
        members = ordered;
      }
      for (int64_t member : members) {
        if (member < 0 || static_cast<uint64_t>(member) >= nodes.size())
          continue;
        auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(
            nodes[static_cast<size_t>(member)]);
        if (!fragment)
          continue;
        sim::SimFuncOp function =
            functions.lookup(fragment.getFunction().getValue());
        if (!function)
          continue;
        auto blocksIt = graphBlocks.find(function.getOperation());
        if (blocksIt == graphBlocks.end())
          continue;
        ArrayRef<Block *> blocks = blocksIt->second;
        if (fragment.getBlock() >= blocks.size())
          return function.emitOpError(
              "compute-graph fragment block is out of range");
        Block *block = blocks[fragment.getBlock()];
        result.blockRanks[block] = rank;
        if (fragment.getBlock() == 0)
          result.entryRanks[function.getOperation()] = rank;
        if (refined && rank != std::numeric_limits<uint32_t>::max())
          ++rank;
      }
      if (!refined && rank != std::numeric_limits<uint32_t>::max())
        ++rank;
    }
  }
  SmallVector<Operation *> preemptions;
  design.walk([&](Operation *op) {
    if (schedule::has<schedule::Field::ActivePreemptionAfter>(op) ||
        schedule::has<schedule::Field::ActivePreemptionRuns>(op))
      preemptions.push_back(op);
  });
  if (!preemptions.empty()) {
    // Preserve the relative order of every ordinary rank while reserving
    // positions for the selected source handoffs. A continuation follows its
    // peers' current bodies, not every unrelated Active event in the design.
    for (auto &[function, value] : result.entryRanks) {
      if (value >= UINT32_MAX / 2)
        return failure();
      value *= 2;
    }
    for (auto &[block, value] : result.blockRanks) {
      if (value >= UINT32_MAX / 2)
        return failure();
      value *= 2;
    }
    // A local feedback interleaving is not closed under incoming activations.
    // For example, a FIFO can publish empty=0 before its combinational return
    // pointer has updated. If an interrupted consumer reads the old pointer,
    // that later update occurs while its event control is unarmed and is lost.
    // Settle independent input cones before starting that consumer. Do not
    // impose this order on inputs whose publication values depend on the
    // interrupted owner: those use the source-ordered handoffs below.
    //
    // Only a handoff inside the body exposes partial publications and reads
    // inputs before it ends. A virtual re-arm follows the complete body.
    DenseSet<Operation *> interrupted;
    for (Operation *op : preemptions)
      if (!schedule::has<schedule::Field::ActivePreemptionRearm>(op))
        interrupted.insert(op->getParentOfType<sim::SimFuncOp>());
    PreemptionInputAnalysis inputs(design, graph, functions, interrupted);
    // Realize the chosen maximal-run order, not just its final handoff.
    // Prefix input constraints can raise the interrupted owner past its peers'
    // old ranks. Assigning only the final continuation would then run those
    // peers first and lose the exact search's minimum-handoff schedule.
    // Solve all selected phase constraints together; unchanged actors keep
    // their original relative priorities and are only read as prerequisites.
    struct Phase {
      uint32_t rank = 0;
      unsigned incoming = 0;
      SmallVector<unsigned> successors;
      sim::SimFuncOp function;
      SmallVector<Block *> blocks;
      bool selected = false;
    };
    SmallVector<Phase> phases;
    DenseMap<Operation *, unsigned> starts;
    auto startPhase = [&](sim::SimFuncOp function, bool selected) {
      auto [entry, inserted] = starts.try_emplace(function, phases.size());
      unsigned id = entry->second;
      if (inserted) {
        Phase phase;
        phase.function = function;
        phase.rank = result.entryRanks.lookup(function);
        phase.blocks.push_back(&function.getBody().front());
        function.walk([&](Operation *wait) {
          if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(wait)) {
            Block *body = wait->getSuccessor(0);
            phase.blocks.push_back(body);
            phase.rank = std::max(phase.rank, result.blockRanks.lookup(body));
          }
        });
        phases.push_back(std::move(phase));
      }
      phases[id].selected |= selected;
      return id;
    };
    auto edge = [&](unsigned from, unsigned to) {
      phases[from].successors.push_back(to);
      ++phases[to].incoming;
    };
    // Producer ordering needs every interrupted actor's final phase, so the
    // input queries run after all run orders have been laid out.
    struct InputQuery {
      sim::SimFuncOp owner;
      SmallVector<sim::SimFuncOp> peers;
      unsigned prefix, final;
    };
    SmallVector<InputQuery> inputQueries;
    DenseMap<Operation *, unsigned> finalPhases;
    DenseMap<Operation *, ArrayAttr> peerOrders;
    DenseMap<Operation *, SmallVector<Block *>> continuations;
    SmallVector<sim::SimFuncOp> owners;
    llvm::MapVector<Attribute, SmallVector<Operation *>> runGroups;
    for (Operation *op : preemptions) {
      auto branch = dyn_cast<BranchOpInterface>(op);
      if (!branch || op->getNumSuccessors() != 1)
        return failure();
      auto function = op->getParentOfType<sim::SimFuncOp>();
      if (auto runs =
              schedule::get<schedule::Field::ActivePreemptionRuns>(op)) {
        auto resume =
            schedule::get<schedule::Field::ActivePreemptionResume>(op);
        if (!resume || resume.getValue().isNegative() ||
            resume.getValue().getActiveBits() > 32 || resume.getUInt() == 0 ||
            resume.getUInt() >= runs.size() ||
            runs[resume.getUInt()] != FlatSymbolRefAttr::get(function))
          return op->emitError("Active preemption has an invalid resumed run");
        runGroups[runs].push_back(op);
        continue;
      }
      auto order = schedule::get<schedule::Field::ActivePreemptionAfter>(op);
      auto [entry, inserted] = peerOrders.try_emplace(function, order);
      if (inserted)
        owners.push_back(function);
      else if (entry->second != order)
        return op->emitError(
            "Active preemptions disagree on source phase order");
      continuations[function].push_back(op->getSuccessor(0));
    }
    for (auto function : owners) {
      SmallVector<sim::SimFuncOp> peers;
      for (Attribute raw : peerOrders.lookup(function)) {
        auto name = dyn_cast<FlatSymbolRefAttr>(raw);
        auto peer = name ? functions.lookup(name.getValue()) : sim::SimFuncOp{};
        if (!peer || peer.getBody().empty())
          return function.emitError(
              "Active preemption has a stale source actor");
        peers.push_back(peer);
      }
      unsigned prefix = startPhase(function, true), previous = prefix;
      for (auto peer : peers) {
        unsigned current = startPhase(peer, true);
        edge(previous, current);
        previous = current;
      }
      unsigned suffix = phases.size();
      Phase phase;
      phase.selected = true;
      phase.blocks = continuations.lookup(function);
      for (Block *block : phase.blocks)
        phase.rank = std::max(phase.rank, result.blockRanks.lookup(block));
      phases.push_back(std::move(phase));
      edge(previous, suffix);
      finalPhases[function] = suffix;
      if (interrupted.contains(function))
        inputQueries.push_back({function, std::move(peers), prefix, suffix});
    }
    // Complete run paths preserve source phases even when several actors
    // are interrupted, or one actor hands off more than once. A virtual
    // re-arm gets its own node just like a continuation containing statements.
    for (auto &[rawOrder, sites] : runGroups) {
      auto order = cast<ArrayAttr>(rawOrder);
      SmallVector<unsigned> path;
      SmallVector<sim::SimFuncOp> actors;
      DenseSet<Operation *> seen;
      for (Attribute raw : order) {
        auto name = dyn_cast<FlatSymbolRefAttr>(raw);
        auto actor =
            name ? functions.lookup(name.getValue()) : sim::SimFuncOp{};
        if (!actor || actor.getBody().empty())
          return design.emitError("Active run order has a stale source actor");
        actors.push_back(actor);
        if (seen.insert(actor).second) {
          path.push_back(startPhase(actor, true));
        } else {
          path.push_back(phases.size());
          Phase phase;
          phase.selected = true;
          phases.push_back(std::move(phase));
        }
      }
      for (Operation *site : sites) {
        unsigned resume =
            schedule::get<schedule::Field::ActivePreemptionResume>(site)
                .getUInt();
        unsigned previous = resume;
        while (previous && actors[--previous] != actors[resume]) {
        }
        if (actors[previous] != actors[resume])
          return site->emitError("Active resumed run has no preceding run");
        Block *block = site->getSuccessor(0);
        Phase &phase = phases[path[resume]];
        phase.blocks.push_back(block);
        phase.rank = std::max(phase.rank, result.blockRanks.lookup(block));
      }
      seen.clear();
      for (auto [index, actor] : llvm::enumerate(actors)) {
        if (!seen.insert(actor).second && phases[path[index]].blocks.empty())
          return actor.emitError(
              "Active run order has no continuation for a run");
        if (index)
          edge(path[index - 1], path[index]);
      }
      for (Operation *site : sites) {
        auto owner = site->getParentOfType<sim::SimFuncOp>();
        unsigned prefix = starts.lookup(owner);
        SmallVector<sim::SimFuncOp> peers;
        for (auto actor : actors)
          if (actor != owner && !llvm::is_contained(peers, actor))
            peers.push_back(actor);
        unsigned last = actors.size();
        while (last && actors[last - 1] != owner)
          --last;
        if (!last)
          return site->emitError("Active run order omits its own actor");
        finalPhases[owner] = path[last - 1];
        if (interrupted.contains(owner))
          inputQueries.push_back({owner, std::move(peers), prefix,
                                  path[last - 1]});
      }
    }
    for (InputQuery &query : inputQueries) {
      auto &prerequisites = result.preemptionPrerequisites[query.owner];
      bool proved = true;
      SmallVector<sim::SimFuncOp> dependents;
      SmallVector<std::pair<sim::SimFuncOp, sim::SimFuncOp>> after;
      SmallVector<sim::SimFuncOp> afterAll;
      auto producers = inputs.getPrerequisites(
          query.owner, query.peers, proved, dependents, after, afterAll);
      if (!proved)
        result.unprovedPreemptionOwners.insert(query.owner);
      for (auto producer : producers) {
        if (llvm::is_contained(prerequisites, producer))
          continue;
        prerequisites.push_back(producer);
        edge(startPhase(producer, false), query.prefix);
      }
      for (auto dependentProducer : dependents)
        edge(query.final, startPhase(dependentProducer, true));
      for (auto [source, producer] : after) {
        auto final = finalPhases.find(source);
        if (final == finalPhases.end()) {
          result.unprovedPreemptionOwners.insert(query.owner);
          continue;
        }
        edge(final->second, startPhase(producer, true));
      }
      for (auto producer : afterAll)
        for (auto &[source, final] : finalPhases)
          if (interrupted.contains(source))
            edge(final, startPhase(producer, true));
    }
    SmallVector<unsigned> ready;
    for (auto [id, phase] : llvm::enumerate(phases))
      if (!phase.incoming)
        ready.push_back(id);
    for (unsigned index = 0; index < ready.size(); ++index) {
      unsigned id = ready[index];
      if (!phases[id].successors.empty() && phases[id].rank == UINT32_MAX)
        return failure();
      for (unsigned next : phases[id].successors) {
        phases[next].rank = std::max(phases[next].rank, phases[id].rank + 1);
        if (--phases[next].incoming == 0)
          ready.push_back(next);
      }
    }
    if (ready.size() != phases.size())
      return design.emitError(
          "Active source interleavings have cyclic phase constraints");
    for (const Phase &phase : phases) {
      if (!phase.selected)
        continue;
      if (phase.function)
        result.entryRanks[phase.function] = phase.rank;
      for (Block *block : phase.blocks)
        result.blockRanks[block] = phase.rank;
    }
  }
  return result;
}

ArrayRef<sim::SimFuncOp> SimulationScheduleAnalysis::getPreemptionPrerequisites(
    Operation *function) const {
  auto found = preemptionPrerequisites.find(function);
  return found == preemptionPrerequisites.end()
             ? ArrayRef<sim::SimFuncOp>{}
             : ArrayRef<sim::SimFuncOp>(found->second);
}

std::optional<uint32_t>
SimulationScheduleAnalysis::getEntryRank(Operation *function) const {
  auto found = entryRanks.find(function);
  if (found == entryRanks.end())
    return std::nullopt;
  return found->second;
}

std::optional<uint32_t>
SimulationScheduleAnalysis::getBlockRank(Block *block) const {
  auto found = blockRanks.find(block);
  if (found == blockRanks.end())
    return std::nullopt;
  return found->second;
}

} // namespace talos::analysis
