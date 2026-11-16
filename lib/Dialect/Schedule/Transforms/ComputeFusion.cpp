//===- ComputeFusion.cpp - Static process-body fusion helpers ------------===//

#include "ComputeFusion.h"
#include "talos/Analysis/ActivationIdempotenceAnalysis.h"
#include "talos/Analysis/DPIEffectAnalysis.h"
#include "talos/Analysis/GraphAlgorithms.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Analysis/SimulationEffectAnalysis.h"
#include "llvm/ADT/TypeSwitch.h"

#include "talos/Analysis/SimulationAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>
#include <memory>
#include <set>
#include <tuple>
#include <vector>

using namespace mlir;

namespace talos {
ConvexActivationGraph::ConvexActivationGraph(
    sim::SimDesignOp design, schedule::ComputeGraphAttr graph,
    const CombinationalFusionAnalysis *analysis) {
  SymbolTable symbols(design);
  SmallVector<unsigned> owners(graph.getNodes().size(), UINT_MAX);
  for (auto [id, raw] : llvm::enumerate(graph.getNodes())) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment)
      continue;
    auto [found, inserted] =
        indices.try_emplace(fragment.getFunction().getAttr(), indices.size());
    auto function =
        symbols.lookup<sim::SimFuncOp>(fragment.getFunction().getValue());
    bool finite =
        function && (function.getEntryKind() == sim::EntryKind::AlwaysComb ||
                     function.getEntryKind() == sim::EntryKind::Continuous ||
                     function.getEntryKind() == sim::EntryKind::AlwaysLatch ||
                     function.getEntryKind() == sim::EntryKind::PortInput ||
                     function.getEntryKind() == sim::EntryKind::PortOutput);
    if (inserted)
      found->second = successors.size();
    unsigned owner = finite && !inserted ? found->second : successors.size();
    if (owner == successors.size()) {
      parents.push_back(owner);
      successors.emplace_back();
      ownerNames.push_back(fragment.getFunction().getAttr());
    }
    owners[id] = owner;
  }
  DenseMap<unsigned, SmallVector<unsigned>> resumes;
  for (Attribute raw : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(raw);
    if (edge.getKind() == schedule::ComputeEdgeKind::Resume)
      resumes[edge.getSource()].push_back(edge.getTarget());
  }
  for (Attribute raw : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(raw);
    // Conflicts are exclusion constraints, not update/evaluation events.
    // NBA/deferred stages, spawns and suspensions are event-region boundaries.
    // Keeping boundary fragments separate prevents a later timed activation
    // from becoming an immediate path through an entire initial process.
    if (edge.getKind() != schedule::ComputeEdgeKind::Sensitivity &&
        edge.getKind() != schedule::ComputeEdgeKind::ProcessOrder)
      continue;
    if (analysis && !analysis->isLiveSensitivityEdge(edge))
      continue;
    unsigned from = owners[edge.getSource()], to = owners[edge.getTarget()];
    if (from != UINT_MAX && to != UINT_MAX && from != to)
      successors[from].push_back(to);
    if (edge.getKind() == schedule::ComputeEdgeKind::Sensitivity)
      for (unsigned continuation : resumes[edge.getTarget()])
        if (from != UINT_MAX && owners[continuation] != UINT_MAX &&
            from != owners[continuation])
          successors[from].push_back(owners[continuation]);
  }
  for (auto &targets : successors) {
    llvm::sort(targets);
    targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
  }
}

unsigned ConvexActivationGraph::leader(unsigned node) const {
  while (parents[node] != node)
    node = parents[node];
  return node;
}

bool ConvexActivationGraph::isConvex(ArrayRef<StringAttr> members,
                                     SmallVectorImpl<StringAttr> *path) const {
  if (path)
    path->clear();
  DenseSet<unsigned> included, visited;
  SmallVector<unsigned> selected, pending;
  DenseMap<unsigned, unsigned> previous;
  for (StringAttr member : members) {
    auto found = indices.find(member);
    if (found == indices.end())
      return false;
    unsigned node = leader(found->second);
    if (included.insert(node).second)
      selected.push_back(node);
  }
  for (unsigned node : selected)
    for (unsigned target : successors[node]) {
      target = leader(target);
      if (!included.contains(target) && visited.insert(target).second) {
        pending.push_back(target);
        if (path)
          previous[target] = node;
      }
    }
  while (!pending.empty()) {
    unsigned node = pending.pop_back_val();
    for (unsigned target : successors[node]) {
      target = leader(target);
      if (included.contains(target)) {
        if (path) {
          SmallVector<unsigned> reversed{target, node};
          unsigned current = node;
          while (!included.contains(current)) {
            current = previous.at(current);
            reversed.push_back(current);
          }
          for (unsigned owner : llvm::reverse(reversed))
            path->push_back(ownerNames[owner]);
        }
        return false;
      }
      if (visited.insert(target).second) {
        pending.push_back(target);
        if (path)
          previous[target] = node;
      }
    }
  }
  return true;
}

void ConvexActivationGraph::contract(ArrayRef<StringAttr> members) {
  SmallVector<unsigned> nodes;
  for (StringAttr member : members)
    nodes.push_back(leader(indices.lookup(member)));
  llvm::sort(nodes);
  nodes.erase(std::unique(nodes.begin(), nodes.end()), nodes.end());
  if (nodes.empty())
    return;
  unsigned root = nodes.front();
  for (unsigned node : ArrayRef(nodes).drop_front()) {
    parents[node] = root;
    llvm::append_range(successors[root], successors[node]);
    successors[node].clear();
  }
  llvm::sort(successors[root]);
  successors[root].erase(
      std::unique(successors[root].begin(), successors[root].end()),
      successors[root].end());
}

SmallVector<SmallVector<StringAttr>>
ConvexActivationGraph::getSections(ArrayRef<StringAttr> members,
                                   ArrayRef<unsigned> activityDomains) const {
  if (!activityDomains.empty() && activityDomains.size() != members.size())
    return {};
  DenseMap<unsigned, SmallVector<StringAttr>> selected;
  DenseMap<unsigned, unsigned> domains;
  DenseSet<unsigned> conflicts;
  for (auto [index, member] : llvm::enumerate(members))
    if (auto found = indices.find(member); found != indices.end()) {
      unsigned node = leader(found->second);
      unsigned domain = activityDomains.empty() ? 0 : activityDomains[index];
      selected[node].push_back(member);
      auto [existing, inserted] = domains.try_emplace(node, domain);
      if (!inserted && existing->second != domain)
        conflicts.insert(node);
    }
  SmallVector<unsigned> nodes;
  DenseMap<unsigned, SmallVector<unsigned>> edges;
  for (unsigned node = 0; node < successors.size(); ++node) {
    if (leader(node) != node)
      continue;
    nodes.push_back(node);
    for (unsigned target : successors[node])
      if (leader(target) != node)
        edges[node].push_back(leader(target));
  }
  auto components =
      analysis::computeStronglyConnectedComponents<unsigned>(nodes, edges);
  // Independent selected cones can be adjacent in a topological order. They
  // must not become one source owner merely because no boundary happens to
  // lie between them: that would couple activation and knownness fallbacks.
  llvm::IntEqClasses islands(successors.size());
  for (const auto &[source, targets] : edges)
    if (selected.contains(source))
      for (unsigned target : targets)
        if (selected.contains(target) &&
            domains.lookup(source) == domains.lookup(target))
          islands.join(source, target);
  SmallVector<SmallVector<StringAttr>> sections;
  llvm::MapVector<unsigned, SmallVector<StringAttr>> open;
  std::optional<unsigned> currentDomain;
  auto flush = [&] {
    for (auto &[island, section] : open)
      sections.push_back(std::move(section));
    open.clear();
  };
  for (const auto &component : llvm::reverse(components)) {
    unsigned domain = domains.lookup(component.front());
    if (llvm::any_of(component, [&](unsigned node) {
          return !selected.contains(node) || conflicts.contains(node) ||
                 domains.lookup(node) != domain;
        })) {
      flush();
      currentDomain.reset();
      continue;
    }
    if (currentDomain && *currentDomain != domain)
      flush();
    currentDomain = domain;
    for (unsigned node : component)
      llvm::append_range(open[islands.findLeader(node)], selected.lookup(node));
  }
  flush();
  return sections;
}

namespace {

bool isStaticDigitalType(Type type) {
  if (isa<IntegerType, FloatType, sim::LogicType, sim::ContextType,
          sim::BytesType>(type))
    return true;
  if (auto reference = dyn_cast<sim::RefType>(type))
    return isStaticDigitalType(reference.getElementType());
  if (auto net = dyn_cast<sim::NetType>(type))
    return isStaticDigitalType(net.getElementType());
  if (auto driver = dyn_cast<sim::DriverType>(type))
    return isStaticDigitalType(driver.getElementType());
  if (auto packed = dyn_cast<sim::PackedArrayType>(type))
    return isStaticDigitalType(packed.getElementType());
  if (auto unpacked = dyn_cast<sim::UnpackedArrayType>(type))
    return isStaticDigitalType(unpacked.getElementType());
  if (isa<sim::PackedStructType, sim::PackedUnionType>(type)) {
    for (unsigned index = 0, count = sim::getAggregateNumElements(type);
         index != count; ++index)
      if (!isStaticDigitalType(sim::getAggregateElementType(type, index)))
        return false;
    return true;
  }
  return false;
}

bool hasOnlyStaticDigitalValues(Operation *operation) {
  return llvm::all_of(operation->getOperandTypes(), isStaticDigitalType) &&
         llvm::all_of(operation->getResultTypes(), isStaticDigitalType);
}

bool hasOnlyStaticDigitalOrTimeValues(Operation *operation) {
  auto eligible = [](Type type) {
    return isStaticDigitalType(type) || isa<sim::TimeType>(type);
  };
  return llvm::all_of(operation->getOperandTypes(), eligible) &&
         llvm::all_of(operation->getResultTypes(), eligible);
}

bool hasConcreteDescriptor(Value value,
                           const analysis::HandleFacts &provenance) {
  auto found = provenance.find(value);
  if (found == provenance.end() || !found->second.descriptor)
    return false;
  return found->second.resource == schedule::ComputeResourceKind::Storage ||
         found->second.resource == schedule::ComputeResourceKind::Net;
}

bool hasConcreteHandleValues(Operation *operation,
                             const analysis::HandleFacts &provenance) {
  auto check = [&](Value value) {
    Type type = value.getType();
    if (!isa<sim::RefType, sim::NetType, sim::DriverType>(type))
      return true;
    // A private slot of the activation is concrete without a descriptor.
    if (auto found = provenance.find(value);
        found != provenance.end() &&
        found->second.resource == schedule::ComputeResourceKind::Local)
      return true;
    // A callee's reference formal is instantiated at each call site, where
    // the actual handles must independently satisfy this check.
    if (auto found = provenance.find(value);
        found != provenance.end() && found->second.formal)
      if (auto function = operation->getParentOfType<sim::SimFuncOp>())
        if (function.getEntryKind() == sim::EntryKind::Function)
          return true;
    return hasConcreteDescriptor(value, provenance);
  };
  return llvm::all_of(operation->getOperands(), check) &&
         llvm::all_of(operation->getResults(), check);
}

bool isEligibleNBA(sim::SimNBAEnqueueOp enqueue) {
  schedule::NBASiteAttr site = enqueue.getSiteAttr();
  return site && !enqueue.getClockingOutputAttr() && !enqueue.getDelay() &&
         !site.getTiming() &&
         (site.getStorage() == schedule::ComputeNBAStorageKind::FixedSlot ||
          site.getStorage() ==
              schedule::ComputeNBAStorageKind::RootAccumulator);
}

bool rangesOverlap(schedule::ComputeEffectAttr lhs,
                   schedule::ComputeEffectAttr rhs) {
  if (lhs.getTarget() != schedule::ComputeTargetKind::Descriptor ||
      rhs.getTarget() != schedule::ComputeTargetKind::Descriptor ||
      lhs.getResource() != rhs.getResource() ||
      lhs.getDescriptor() != rhs.getDescriptor() || lhs.getDynamic() ||
      rhs.getDynamic() || lhs.getWidth() == 0 || rhs.getWidth() == 0)
    return false;
  uint64_t lhsEnd = lhs.getLow() + lhs.getWidth();
  uint64_t rhsEnd = rhs.getLow() + rhs.getWidth();
  if (lhsEnd < lhs.getLow() || rhsEnd < rhs.getLow())
    return false;
  return lhs.getLow() < rhsEnd && rhs.getLow() < lhsEnd;
}

bool isComputeBodyFusionEligibleImpl(
    sim::SimFuncOp function,
    const analysis::HandleDataflowAnalysis &provenanceAnalysis,
    llvm::DenseMap<Operation *, bool> &cache,
    llvm::SmallPtrSetImpl<Operation *> &active, bool primitiveDriverOps) {
  if (!function || function.isExternal() ||
      !llvm::all_of(function.getFunctionType().getInputs(),
                    isStaticDigitalType))
    return false;
  if (auto cached = cache.find(function.getOperation()); cached != cache.end())
    return cached->second;
  if (!active.insert(function.getOperation()).second)
    return false;

  sim::SimDesignOp design = function->getParentOfType<sim::SimDesignOp>();
  auto handles = provenanceAnalysis.analyze(function);
  const auto &provenance = handles.facts;
  bool eligible = true;
  function.walk([&](Operation *operation) {
    if (!eligible || operation == function.getOperation() ||
        !handles.isExecutable(operation->getBlock()))
      return;

    // These operations define the only control and scheduler interaction that
    // a fused process may retain. In particular, termination polling is
    // process-independent, while finish/fatal/stop and dynamic control are not.
    if (isa<cf::BranchOp, cf::CondBranchOp, sim::SimReturnOp,
            sim::SimSuspendChangeOp, sim::SimSuspendEdgeOp,
            sim::SimSuspendAnyOp, sim::SimTerminationRequestedOp,
            sim::SimCoveragePointHitOp>(operation)) {
      eligible = hasOnlyStaticDigitalValues(operation) &&
                 hasConcreteHandleValues(operation, provenance);
      return;
    }

    if (auto call = dyn_cast<sim::SimCallOp>(operation)) {
      sim::SimFuncOp callee = design ? design.lookupSymbol<sim::SimFuncOp>(
                                           call.getCalleeAttr().getValue())
                                     : sim::SimFuncOp{};
      eligible = callee && callee.getEntryKind() == sim::EntryKind::Function &&
                 hasOnlyStaticDigitalValues(operation) &&
                 hasConcreteHandleValues(operation, provenance) &&
                 isComputeBodyFusionEligibleImpl(callee, provenanceAnalysis,
                                                 cache, active, false);
      return;
    }

    if (auto display = dyn_cast<sim::SimDisplayOp>(operation)) {
      // Static formatting stays on a cold branch of the fused activation; it
      // is not executed by the ordinary clock path.
      eligible = display.getScopeAttr() &&
                 hasOnlyStaticDigitalValues(display) &&
                 hasConcreteHandleValues(display, provenance);
      return;
    }

    // An immediate assertion's failure report. IEEE 1800-2023 20.10: $error
    // records a nonterminating error; 20.3.1: $time is fixed within the time
    // slot of the activation; 20.11: the assertion enable is control state no
    // fused member writes. Running the members back to back reorders them
    // only within the slot, which 4.7 permits.
    if (isa<sim::SimErrorOp, sim::SimTimeNowOp, sim::SimAssertionEnabledOp>(
            operation)) {
      eligible = hasOnlyStaticDigitalValues(operation);
      return;
    }

    if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(operation)) {
      eligible = isEligibleNBA(enqueue) &&
                 hasOnlyStaticDigitalValues(operation) &&
                 hasConcreteHandleValues(operation, provenance);
      return;
    }

    if (primitiveDriverOps && isa<sim::SimTimeConstantOp>(operation)) {
      eligible = hasOnlyStaticDigitalOrTimeValues(operation);
      return;
    }

    if (primitiveDriverOps && isa<sim::SimDriverDriveInertialOp>(operation)) {
      eligible = hasOnlyStaticDigitalOrTimeValues(operation) &&
                 hasConcreteHandleValues(operation, provenance);
      return;
    }

    if (auto alloc = dyn_cast<sim::SimRefAllocOp>(operation)) {
      eligible = analysis::isPlainValueType(alloc.getType().getElementType()) &&
                 hasOnlyStaticDigitalValues(operation) &&
                 hasConcreteHandleValues(operation, provenance);
      return;
    }

    if (isa<sim::SimRefLoadOp, sim::SimRefStoreOp, sim::SimNetReadOp,
            sim::SimDriverDriveOp, sim::SimDriverDriveChangedOp>(operation) ||
        (primitiveDriverOps && isa<sim::SimDriverReadOp>(operation))) {
      eligible = hasOnlyStaticDigitalValues(operation) &&
                 hasConcreteHandleValues(operation, provenance);
      return;
    }

    // Pure arithmetic, aggregate manipulation, and descriptor views are safe
    // only when they remain within the checked static-digital type universe.
    // Every other operation carrying an actor, scheduler, RNG, heap, IO, or
    // managed effect is rejected instead of relying on an open-ended exclusion
    // list.
    eligible = isMemoryEffectFree(operation) &&
               hasOnlyStaticDigitalValues(operation) &&
               hasConcreteHandleValues(operation, provenance);
  });
  active.erase(function.getOperation());
  cache[function.getOperation()] = eligible;
  return eligible;
}

/// Resolves a storage write through a subroutine formal to the physical
/// roots its call sites pass. IEEE 1800-2023 13.5 copies `output` and `inout`
/// values into the actuals when the subroutine returns, and 13.5.2 makes a
/// `ref` formal an alias of its actual. Either way the actual is the storage
/// written. The simulation IR passes all three as references, so a caller's
/// own effect summary does not record the write; only the callee's
/// formal-target effect does.
class FormalWriteResolver {
public:
  FormalWriteResolver(
      sim::SimDesignOp design,
      const analysis::HandleDataflowAnalysis &provenanceAnalysis)
      : design(design), provenanceAnalysis(provenanceAnalysis) {}

  /// Calls `emit` with a descriptor-target copy of `effect` for every storage
  /// root that `owner`'s formal can reach. Returns false when some call path
  /// cannot be resolved, in which case the reported roots are incomplete.
  bool resolve(
      StringAttr owner, schedule::ComputeEffectAttr effect,
      llvm::function_ref<void(uint64_t, schedule::ComputeEffectAttr)> emit) {
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
      auto function = functions.lookup(name.getValue());
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
        if (target.resource == schedule::ComputeResourceKind::Local)
          continue;
        if (target.resource != schedule::ComputeResourceKind::Storage) {
          complete = false;
        } else if (target.descriptor) {
          // Resolve physical roots, not combinations of call paths. Widen
          // formal subranges within each root until an offset-sensitive call
          // proof is available; unrelated roots stay independent.
          emit(*target.descriptor,
               schedule::ComputeEffectAttr::get(
                   design.getContext(), effect.getEffect(), target.resource,
                   schedule::ComputeTargetKind::Descriptor, *target.descriptor,
                   0, 0, target.rootWidth, true, effect.getDeferred(),
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

private:
  void index() {
    indexed = true;
    for (sim::SimFuncOp function :
         design.getBody().front().getOps<sim::SimFuncOp>())
      functions[function.getSymName()] = function;
    design.walk([&](Operation *op) {
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

  sim::SimDesignOp design;
  const analysis::HandleDataflowAnalysis &provenanceAnalysis;
  bool indexed = false;
  bool unsupportedCalls = false;
  llvm::StringMap<sim::SimFuncOp> functions;
  llvm::StringMap<SmallVector<Operation *>> callers;
  DenseMap<Operation *, analysis::HandleFacts> provenance;
};

} // namespace

CombinationalFusionAnalysis::CombinationalFusionAnalysis(
    sim::SimDesignOp design,
    const analysis::HandleDataflowAnalysis &provenanceAnalysis,
    analysis::ActivationMemoryAnalysis::DependencyMode mode,
    ObservationContext observations)
    : observationContext(observations), design(design),
      provenance(&provenanceAnalysis), dependencyMode(mode) {
  auto graph = design.getComputeGraphAttr();
  // Full foreign mutation needs a range-scoped invalidation route for this
  // idempotent kernel. Existing externally driven evaluators retain their
  // own admission; do not silently extend their contract here.
  unsupported = !graph || graph.getVpi() == schedule::ComputeVPIMode::Full;
  if (!graph)
    return;
  // A DPI call reaches the design only through context exports (IEEE
  // 1800-2023 35.5.1.3, 35.5.3).
  unsupported |= analysis::DPIEffectAnalysis(design).anyCallMayAccessDesign();
  design.walk([&](Operation *op) {
    unsupported |= isa<sim::SimOverrideOp, sim::SimReleaseOverrideOp,
                       sim::SimDynamicOverrideOp, sim::SimProcessControlOp,
                       sim::SimControlDisableOp>(op);
  });
  if (unsupported)
    return;
  FormalWriteResolver formals(design, provenanceAnalysis);
  auto resolveFormal = [&](StringAttr owner,
                           schedule::ComputeEffectAttr effect) {
    unsupported |= !formals.resolve(
        owner, effect,
        [&](uint64_t descriptor, schedule::ComputeEffectAttr write) {
          storageWriters[descriptor].push_back({owner, write});
        });
  };
  for (Attribute attr : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attr);
    if (!fragment)
      continue;
    if (fragment.getTier() != schedule::ComputeTierKind::Native)
      nonNativeOwners.insert(fragment.getFunction().getAttr());
    for (Attribute attr : fragment.getEffects()) {
      auto effect = cast<schedule::ComputeEffectAttr>(attr);
      if (effect.getEffect() != schedule::ComputeEffectKind::Write &&
          effect.getEffect() != schedule::ComputeEffectKind::NBA &&
          effect.getEffect() != schedule::ComputeEffectKind::Drive)
        continue;
      if (effect.getResource() != schedule::ComputeResourceKind::Storage &&
          effect.getResource() != schedule::ComputeResourceKind::Net &&
          effect.getResource() != schedule::ComputeResourceKind::Unknown)
        continue;
      if (effect.getResource() == schedule::ComputeResourceKind::Storage &&
          effect.getTarget() == schedule::ComputeTargetKind::Formal) {
        resolveFormal(fragment.getFunction().getAttr(), effect);
        continue;
      }
      if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
          effect.getResource() == schedule::ComputeResourceKind::Unknown) {
        unsupported = true;
        continue;
      }
      auto root = analysis::ActivationMemoryAnalysis::getRoot(
          effect.getResource(), effect.getDescriptor());
      if (!root) {
        unsupported = true;
        continue;
      }
      storageWriters[*root].push_back(
          {fragment.getFunction().getAttr(), effect});
    }
  }
}

namespace {
using ActivationRange = analysis::ActivationMemoryAnalysis::Range;
using ActivationRanges = analysis::ActivationMemoryAnalysis::Ranges;
bool activationRangesOverlap(const ActivationRange &a,
                             const ActivationRange &b) {
  return a.root == b.root && a.low < b.low + b.width && b.low < a.low + a.width;
}
bool activationRangeCovered(ArrayRef<ActivationRange> ranges,
                            const ActivationRange &range) {
  SmallVector<std::pair<uint64_t, uint64_t>> intervals;
  for (const auto &r : ranges)
    if (r.root == range.root)
      intervals.emplace_back(r.low, r.low + r.width);
  llvm::sort(intervals);
  uint64_t covered = range.low;
  for (auto [low, high] : intervals) {
    if (low > covered)
      break;
    covered = std::max(covered, high);
  }
  return covered >= range.low + range.width;
}
} // namespace

std::string CombinationalFusionFailure::getMessage() const {
  switch (reason) {
  case Reason::None:
    return {};
  case Reason::Activation:
    if (unsupported)
      return (analysis::stringifyActivationFailure(activation) + " (" +
              unsupported->getStringRef() + ")")
          .str();
    return analysis::stringifyActivationFailure(activation).str();
  case Reason::UnsupportedOwner:
    return "owner or unsupported effects";
  case Reason::IncompleteWrites:
    return "incomplete writes";
  case Reason::SensitivityRegion:
    return "sensitivity region";
  case Reason::ImpreciseSensitivity:
    return "imprecise sensitivity";
  case Reason::UnwatchedLiveIn:
    return (Twine("unwatched live-in on storage ") + Twine(storage)).str();
  case Reason::IncomingOutputState:
    return "incoming output state";
  case Reason::MissingWriterInventory:
    return "missing writer inventory";
  case Reason::NonExclusiveWriter:
    return "non-exclusive writer";
  case Reason::ActivationEntry:
    return "activation entry";
  case Reason::UnsupportedObservations:
    return "unsupported observations";
  case Reason::MissingActivationProof:
    return "missing activation proof";
  case Reason::UnknownWatchedResource:
    return "unknown watched resource";
  case Reason::UnresolvedWatchedStorage:
    return "unresolved watched storage";
  case Reason::ToggleCoverage:
    return (Twine("toggle coverage on storage ") + Twine(storage)).str();
  case Reason::OutsideWatch:
    return (Twine("outside watch in ") + owner.getValue() +
            " on repeated storage " + Twine(storage))
        .str();
  case Reason::ObservableState:
    return (Twine("observable storage ") + Twine(storage) +
            (owner ? Twine(" via ") + owner.getValue() : Twine()))
        .str();
  case Reason::OutsideObserver:
    return (Twine("outside watch in ") + owner.getValue() + " on storage " +
            Twine(storage))
        .str();
  }
  llvm_unreachable("unknown combinational fusion failure");
}

static bool isInterleavableKind(sim::SimFuncOp function) {
  auto kind = function.getEntryKind();
  return kind == sim::EntryKind::AlwaysComb ||
         kind == sim::EntryKind::Continuous ||
         kind == sim::EntryKind::PortInput ||
         kind == sim::EntryKind::PortOutput;
}

void CombinationalFusionAnalysis::prepareActivations() const {
  auto design = this->design;
  if (unsupported || design.getBody().empty())
    return;
  SmallVector<sim::SimFuncOp> functions;
  for (auto function : design.getBody().front().getOps<sim::SimFuncOp>())
    if (!function.isExternal() && isInterleavableKind(function) &&
        function.getHomeRegion() == sim::EventRegion::Active &&
        !nonNativeOwners.contains(function.getSymNameAttr()) &&
        !activations.contains(function))
      functions.push_back(function);
  if (!analysis::walksConcurrently(design, functions.size()))
    return;
  // With every design function in the handle cache, a worker reads the
  // callees it visits and solves only its own private activation clones.
  provenance->prepare(design);
  std::vector<std::unique_ptr<analysis::ActivationRegionAnalysis>> built(
      functions.size());
  analysis::parallelForChunked(
      design.getContext(), functions.size(), [&](size_t index) {
        if (isComputeBodyFusionEligible(functions[index], *provenance))
          built[index] = std::make_unique<analysis::ActivationRegionAnalysis>(
              analysis::prepareActivation(functions[index]), *provenance,
              dependencyMode);
      });
  for (auto [function, activation] : llvm::zip_equal(functions, built))
    if (activation)
      activations[function] = std::move(activation);
}

std::optional<CombinationalFusionBody> CombinationalFusionAnalysis::analyze(
    sim::SimFuncOp function, const analysis::HandleDataflowAnalysis &analysis,
    bool interleaved, CombinationalFusionFailure *failureReason,
    bool finalValuesOnly) const {
  using Reason = CombinationalFusionFailure::Reason;
  if (failureReason)
    *failureReason = {};
  auto reject = [&](CombinationalFusionFailure reason)
      -> std::optional<CombinationalFusionBody> {
    if (failureReason)
      *failureReason = reason;
    return std::nullopt;
  };
  bool kind =
      function && (function.getEntryKind() == sim::EntryKind::AlwaysComb ||
                   (interleaved && isInterleavableKind(function)));
  if (unsupported || !function || function.isExternal() || !kind ||
      function.getHomeRegion() != sim::EventRegion::Active ||
      nonNativeOwners.contains(function.getSymNameAttr()) ||
      !isComputeBodyFusionEligible(function, analysis))
    return reject({Reason::UnsupportedOwner});
  if (interleaved) {
    auto &activation = activations[function];
    if (!activation)
      activation = std::make_unique<analysis::ActivationRegionAnalysis>(
          analysis::prepareActivation(function), analysis, dependencyMode);
    if (!activation->isValid()) {
      CombinationalFusionFailure failure{Reason::Activation,
                                         activation->getFailureReason()};
      if (Operation *op = activation->getMemory().getUnsupportedOperation())
        failure.unsupported = op->getName();
      return reject(failure);
    }
    const auto &memory = activation->getMemory();
    if (memory.getMayWrites().empty())
      return reject({Reason::IncompleteWrites});
    if (observationContext == ObservationContext::RegionBoundary) {
      if (!memory.hasCompleteWrites())
        return reject({Reason::IncompleteWrites});
      auto inputs = memory.hasValueDependencies() ? memory.getFinalInputs()
                                                  : memory.getLiveIns();
      for (const auto &input : inputs)
        if (llvm::any_of(memory.getMayWrites(), [&](const auto &write) {
              return activationRangesOverlap(input, write);
            }))
          return reject({Reason::IncomingOutputState});
    }
    std::optional<bool> idempotent;
    if (!memory.hasCompleteWrites()) {
      // IEEE 1800-2023 4.3/9.4.2/10.4.1: an omitted packed-cell update
      // holds exactly the old value, like an explicit self-assignment. Only
      // the final-value/observer proof may use that equivalence. Keep the
      // original conditional stores, may/must ranges and source sensitivity;
      // ordinary fusion and strict repeatability still require completeness.
      bool packed = llvm::all_of(memory.getWrites(), [](const auto &entry) {
        auto store = dyn_cast<sim::SimRefStoreOp>(entry.first);
        return store &&
               isa_and_nonnull<IntegerType, sim::LogicType>(
                   sim::getPackedScalarType(store.getValue().getType()));
      });
      if (!finalValuesOnly ||
          function.getEntryKind() != sim::EntryKind::AlwaysComb ||
          !memory.hasValueDependencies() || !packed)
        return reject({Reason::IncompleteWrites});
      idempotent = analysis::hasIdempotentStateTransition(
          activation->getActivationFunction(), memory, analysis);
      if (!*idempotent)
        return reject({Reason::IncompleteWrites});
    }
    Operation *suspend = activation->getSuspension();
    SmallVector<Value> watched;
    sim::EventRegionAttr region;
    if (auto change = dyn_cast<sim::SimSuspendChangeOp>(suspend)) {
      watched.push_back(change.getWatched());
      region = change.getResumeRegionAttr();
    } else {
      auto any = cast<sim::SimSuspendAnyOp>(suspend);
      llvm::append_range(watched, any.getWatched());
      region = any.getResumeRegionAttr();
    }
    if (watched.empty() ||
        (region && region.getValue() != sim::EventRegion::Active))
      return reject({Reason::SensitivityRegion});
    auto facts = analysis.derive(function);
    ActivationRanges watches;
    for (Value watch : watched) {
      auto found = facts.find(watch);
      auto span = sim::getProvenanceSpan(watch.getType());
      if (found == facts.end() || !found->second.descriptor ||
          found->second.dynamic || !span || found->second.width != *span)
        return reject({Reason::ImpreciseSensitivity});
      auto &fact = found->second;
      auto root = analysis::ActivationMemoryAnalysis::getRoot(fact.resource,
                                                              *fact.descriptor);
      if (!root)
        return reject({Reason::ImpreciseSensitivity});
      watches.push_back({*root, fact.low, fact.width});
    }
    auto inputs = memory.hasValueDependencies() ? memory.getValueInputs()
                                                : memory.getLiveIns();
    // The transitive observer and publication-slicing certificates may ignore
    // overwritten publications. Ordinary fusion keeps every intermediate input.
    if (finalValuesOnly && memory.hasValueDependencies())
      inputs = memory.getFinalInputs();
    // Every publication and control decision must be independent of incoming
    // output state. Reaching values can discharge old snapshots whose lanes
    // are fully overwritten without hiding an intermediate publication.
    // Physical accesses still drive executable region ordering.
    for (const auto &read : inputs) {
      if (finalValuesOnly &&
          activationRangeCovered(memory.getMayWrites(), read)) {
        if (!idempotent)
          idempotent = analysis::hasIdempotentStateTransition(
              activation->getActivationFunction(), memory, analysis);
        // The activation keeps every state update. Publication slicing groups
        // all source-local snapshots with their writers in the same slice.
        // A retained value is a stable parameter on precisely the paths that
        // use it. Repeating the observer with unchanged inputs cannot count
        // transitions or expose an earlier state version. Writer exclusivity
        // and the transitive output-observer closure are still checked below.
        if (*idempotent)
          continue;
      }
      if (!activationRangeCovered(watches, read))
        return reject({Reason::UnwatchedLiveIn,
                       analysis::ActivationRegionAnalysis::FailureReason::None,
                       read.root});
      if (llvm::any_of(memory.getMayWrites(), [&](const auto &write) {
            return activationRangesOverlap(read, write);
          }))
        return reject({Reason::IncomingOutputState});
    }
    for (const auto &write : memory.getMayWrites()) {
      auto writers = storageWriters.find(write.root);
      if (writers == storageWriters.end())
        return reject({Reason::MissingWriterInventory});
      for (auto [owner, effect] : writers->second) {
        if (owner == function.getSymNameAttr())
          continue;
        if (effect.getDynamic() || !effect.getWidth() ||
            effect.getLow() > UINT64_MAX - effect.getWidth() ||
            activationRangesOverlap(
                write, {write.root, effect.getLow(), effect.getWidth()}))
          return reject({Reason::NonExclusiveWriter});
      }
    }
    auto start =
        dyn_cast<cf::BranchOp>(function.getBody().front().getTerminator());
    if (!start)
      return reject({Reason::ActivationEntry});
    return CombinationalFusionBody{
        start.getDest(), suspend, {}, {}, activation.get()};
  }
  auto &entry = function.getBody().front();
  auto start = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!start || (!interleaved && !start.getDestOperands().empty()))
    return std::nullopt;
  for (Operation &op : entry.without_terminator())
    if (!isMemoryEffectFree(&op) || !isSpeculatable(&op))
      return std::nullopt;
  CombinationalFusionBody result{start.getDest(), nullptr, {}, {}};
  SmallVector<Value> reads, watches;
  SmallVector<Operation *> stores;
  auto handles = analysis.analyze(function);
  const auto &provenance = handles.facts;
  bool valid = true;
  function.walk([&](Operation *op) {
    if (op == function.getOperation() || !handles.isExecutable(op->getBlock()))
      return;
    if (auto change = dyn_cast<sim::SimSuspendChangeOp>(op)) {
      valid &= !result.suspend;
      result.suspend = op;
      watches.push_back(change.getWatched());
    } else if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op)) {
      valid &= !result.suspend && llvm::all_of(any.getEdges(), [](int32_t e) {
        return e == static_cast<int32_t>(sim::EdgeKind::Change);
      });
      result.suspend = op;
      watches.append(any.getWatched().begin(), any.getWatched().end());
    } else if (auto load = dyn_cast<sim::SimRefLoadOp>(op)) {
      reads.push_back(load.getReference());
    } else if (auto load = dyn_cast<sim::SimNetReadOp>(op)) {
      reads.push_back(load.getNet());
    } else if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
      result.outputs.push_back(store.getReference());
      stores.push_back(op);
    } else if (!isa<cf::BranchOp, cf::CondBranchOp>(op)) {
      valid &= op->getNumRegions() == 0 && isMemoryEffectFree(op);
    }
  });
  if (!valid || !result.suspend || result.outputs.empty() || watches.empty() ||
      result.suspend->getSuccessor(0) != result.activation)
    return std::nullopt;
  auto resumed = cast<BranchOpInterface>(result.suspend)
                     .getSuccessorOperands(0)
                     .getForwardedOperands();
  if (!interleaved && !resumed.empty())
    return std::nullopt;
  // Suspension lowering threads stable handles through block arguments.
  // The activation header has one initial edge and one suspension backedge;
  // a phi receiving itself on that backedge is invariant. Changing carried
  // state is not an idempotent combinational activation and remains separate.
  if (resumed.size() != start.getDestOperands().size())
    return std::nullopt;
  for (auto [argument, initial, next] : llvm::zip_equal(
           result.activation->getArguments(), start.getDestOperands(), resumed))
    if (next != argument && next != initial)
      return std::nullopt;
  if (auto region =
          TypeSwitch<Operation *, sim::EventRegionAttr>(result.suspend)
              .Case<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(
                  [](auto wait) { return wait.getResumeRegionAttr(); })
              .Default(sim::EventRegionAttr{});
      region && region.getValue() != sim::EventRegion::Active)
    return std::nullopt;
  // An always_comb spelling is not a proof that every path assigns its
  // outputs. Retained-state behavior keeps the original activation protocol.
  DominanceInfo dominance(function);
  for (Operation *store : stores)
    if (!dominance.dominates(store, result.suspend))
      return std::nullopt;
  auto precise = [&](Value value) -> const analysis::HandleFact * {
    auto found = provenance.find(value);
    if (found == provenance.end() || !found->second.descriptor ||
        found->second.dynamic || !found->second.width ||
        found->second.low > UINT64_MAX - found->second.width)
      return nullptr;
    return &found->second;
  };
  auto overlap = [](const auto &a, const auto &b) {
    return a.resource == b.resource && a.descriptor == b.descriptor &&
           a.low < b.low + b.width && b.low < a.low + a.width;
  };
  for (Value read : reads) {
    const auto *r = precise(read);
    if (!r || !llvm::any_of(watches, [&](Value watch) {
          const auto *w = precise(watch);
          return w && r->resource == w->resource &&
                 r->descriptor == w->descriptor && w->low <= r->low &&
                 r->low + r->width <= w->low + w->width;
        }))
      return std::nullopt;
  }
  for (auto [index, output] : llvm::enumerate(result.outputs)) {
    const auto *w = precise(output);
    auto type = dyn_cast<sim::RefType>(output.getType());
    auto span = sim::getProvenanceSpan(output.getType());
    if (!w || !type || !sim::getPackedScalarType(type.getElementType()))
      return std::nullopt;
    // Interleaving removes fully internal watches. A phi/select of several
    // fixed views has a may-hull wider than one store: it cannot establish
    // complete coverage of the enclosed range for that removal.
    if (interleaved && (!span || w->width != *span))
      return std::nullopt;
    for (Value read : reads)
      if (overlap(*w, *precise(read)))
        return std::nullopt;
    for (Value previous : ArrayRef(result.outputs).take_front(index)) {
      const auto *p = precise(previous);
      if (!p || overlap(*w, *p))
        return std::nullopt;
    }
    auto writers = storageWriters.find(*w->descriptor);
    if (writers == storageWriters.end())
      return std::nullopt;
    for (auto [owner, effect] : writers->second) {
      if (owner == function.getSymNameAttr())
        continue;
      if (effect.getDynamic() || !effect.getWidth() ||
          effect.getLow() > UINT64_MAX - effect.getWidth() ||
          (w->low < effect.getLow() + effect.getWidth() &&
           effect.getLow() < w->low + w->width))
        return std::nullopt;
    }
  }
  // Cut the implicit wait before topological sorting. The process backedge is
  // not combinational feedback. Every other CFG cycle stays outside the group.
  DenseMap<Block *, unsigned> incoming;
  for (Block &block : llvm::drop_begin(function.getBody()))
    incoming[&block] = 0;
  for (auto &[block, count] : incoming) {
    (void)count;
    if (block->getTerminator() == result.suspend)
      continue;
    if (!isa<cf::BranchOp, cf::CondBranchOp>(block->getTerminator()))
      return std::nullopt;
    for (Block *next : block->getSuccessors()) {
      auto found = incoming.find(next);
      if (found == incoming.end())
        return std::nullopt;
      ++found->second;
    }
  }
  SmallVector<Block *> ready;
  for (Block &block : llvm::drop_begin(function.getBody()))
    if (!incoming.lookup(&block))
      ready.push_back(&block);
  if (ready.size() != 1 || ready.front() != result.activation)
    return std::nullopt;
  for (size_t cursor = 0; cursor < ready.size(); ++cursor) {
    Block *block = ready[cursor];
    if (block->getTerminator() != result.suspend)
      for (Block *next : block->getSuccessors())
        if (--incoming[next] == 0)
          ready.push_back(next);
  }
  if (ready.size() != incoming.size())
    return std::nullopt;
  result.blocks = std::move(ready);
  return result;
}

const CombinationalFusionAnalysis::RepeatableInputs &
CombinationalFusionAnalysis::getRepeatableInputs(bool explainRejections) const {
  auto design = this->design;
  if (repeatableInputs)
    return *repeatableInputs;
  auto &result = repeatableInputs.emplace();
  if (unsupported)
    return result;
  DenseMap<StringAttr, SmallVector<sim::SimSpawnOp, 1>> spawns;
  design.walk([&](sim::SimSpawnOp spawn) {
    spawns[spawn.getCalleeAttr().getAttr()].push_back(spawn);
  });
  prepareActivations();
  // Only the distribution is reported: a remark per process would serialize
  // the design once per rejected process.
  bool report = explainRejections && native::has<native::DebugTiming>(
                                         design->getParentOfType<ModuleOp>());
  llvm::StringMap<uint64_t> rejections;
  auto reject = [&](StringRef reason) {
    if (report)
      ++rejections[reason];
  };
  design.walk([&](sim::SimFuncOp function) {
    auto instances = spawns.find(function.getSymNameAttr());
    if (instances == spawns.end())
      return;
    if (instances->second.size() != 1)
      return reject("shared body");
    auto spawn = instances->second.front();
    auto initializer = spawn->getParentOfType<sim::SimFuncOp>();
    // IEEE 1800-2023 9.2.2.2 and 4.9.1 require initial evaluation of
    // always_comb/continuous processes. Preserve that activation and prove
    // one actor: a unique spawn in a loop is not a unique initializer.
    if (!initializer ||
        initializer.getEntryKind() != sim::EntryKind::RootInitializer ||
        spawn->getBlock() != &initializer.getBody().front())
      return reject("spawn outside the root initializer entry");
    CombinationalFusionFailure failure;
    auto body = analyze(function, *provenance, /*interleaved=*/true,
                        report ? &failure : nullptr);
    if (!body || !body->structured) {
      if (report) {
        std::string message = failure.getMessage();
        // Storage identities and operation names vary per process; the
        // histogram needs the class of failure.
        reject(message.empty()
                   ? "no structured activation"
                   : StringRef(message).split(" on storage ").first);
      }
      return;
    }
    const auto &memory = body->structured->getMemory();
    // IEEE 1800-2023 4.3, 4.9.1, 9.2.2.2 and 9.4.2: these processes run at
    // initialization and watch every live input. With no pending input change,
    // their complete, exclusive outputs already hold the computed values.
    // A repeated write could still create an intermediate transition, even
    // when the final value is unchanged. Keep its source activation predicate.
    // The shared analysis also excludes state-dependent outputs, missing
    // sensitivities, foreign mutation and non-equivalent initial execution.
    // A code owner is not itself a unique actor: distinct instances may have
    // different immutable captures and compete for the same output.
    if (!memory.getRepeatedWrites().empty())
      return reject("repeated writes");
    if (memory.hasMixedPrivateWrites())
      return reject("mixed private writes");
    auto inputs = memory.hasInputDependencies() ? memory.getValueInputs()
                                                : memory.getLiveIns();
    result.try_emplace(function.getSymNameAttr(), inputs.begin(), inputs.end());
  });
  if (report) {
    SmallVector<StringRef> ordered;
    for (const auto &entry : rejections)
      ordered.push_back(entry.first());
    llvm::sort(ordered, [&](StringRef lhs, StringRef rhs) {
      return std::make_pair(rejections.lookup(rhs), rhs) <
             std::make_pair(rejections.lookup(lhs), lhs);
    });
    for (StringRef reason : ordered)
      llvm::errs() << "talos repeatable rejection: count="
                   << rejections.lookup(reason) << " reason=" << reason << '\n';
  }
  return result;
}

llvm::DenseSet<StringAttr> schedule::collectRepeatableCombinationalActivations(
    sim::SimDesignOp design, const analysis::HandleDataflowAnalysis &handles,
    llvm::function_ref<void(StringAttr,
                            const analysis::ActivationMemoryAnalysis &)>
        record) {
  CombinationalFusionAnalysis combinational(
      design, handles,
      analysis::ActivationMemoryAnalysis::DependencyMode::ReachingValues);
  llvm::DenseSet<StringAttr> result;
  const auto &certified =
      combinational.getRepeatableInputs(/*explainRejections=*/true);
  design.walk([&](sim::SimFuncOp function) {
    StringAttr owner = function.getSymNameAttr();
    if (!certified.contains(owner))
      return;
    result.insert(owner);
    if (record) {
      auto body =
          combinational.analyze(function, handles, /*interleaved=*/true);
      assert(body && body->structured && "certified activation is cached");
      record(owner, body->structured->getMemory());
    }
  });
  return result;
}

std::optional<analysis::Ranges>
CombinationalFusionAnalysis::getSchedulingWatchRanges(
    StringAttr owner, schedule::ComputeEffectAttr watch) const {
  if (!watch || watch.getTarget() != schedule::ComputeTargetKind::Descriptor ||
      !watch.getWidth() || watch.getLow() > UINT64_MAX - watch.getWidth())
    return std::nullopt;
  auto root = analysis::ActivationMemoryAnalysis::getRoot(
      watch.getResource(), watch.getDescriptor());
  if (!root)
    return std::nullopt;
  analysis::Ranges ranges{{*root, watch.getLow(), watch.getWidth()}};
  if (watch.getEffect() != schedule::ComputeEffectKind::Watch ||
      watch.getTrigger() != schedule::ComputeTriggerKind::Change ||
      watch.getDynamic() || watch.getDeferred())
    return ranges;
  // IEEE 1800-2023 4.3 permits an equivalent algorithm. Complete exclusive
  // outputs, single publications, and every value/control/target input prove
  // that an unused-lane wake cannot change state or produce an update event.
  // This is not a final-value-only proof: intermediate transitions must stay
  // observable (4.6, 9.4.2), so repeated-write owners are never refined here.
  // Unfused source waits retain their implicit sensitivity (9.2.2.2.1).
  // Planning and composed union waits use these same effective lanes. The
  // source-order/snapshot and observer proofs still govern statement fusion
  // (4.6(a)), and NBA staging is unchanged (10.4.2).
  const auto &inputs = getRepeatableInputs();
  auto found = inputs.find(owner);
  // Match native fanout's no-live-input fallback: retain an owner even when
  // no watched input can change its constant outputs.
  if (found == inputs.end() || found->second.empty())
    return ranges;
  return analysis::intersect(ranges, found->second);
}

bool CombinationalFusionAnalysis::isLiveSensitivityEdge(
    schedule::ComputeEdgeAttr edge) const {
  // Keep all process order and non-change event controls (4.6(a), 9.4.2).
  if (edge.getKind() != schedule::ComputeEdgeKind::Sensitivity)
    return true;
  auto design = this->design;
  auto graph = design.getComputeGraphAttr();
  auto source = dyn_cast<schedule::ComputeFragmentAttr>(
      graph.getNodes()[edge.getSource()]);
  auto target = dyn_cast<schedule::ComputeFragmentAttr>(
      graph.getNodes()[edge.getTarget()]);
  if (!source || !target)
    return true;
  auto watch = edge.getResource();
  auto ranges = getSchedulingWatchRanges(target.getFunction().getAttr(), watch);
  if (!ranges)
    return true;
  bool matched = false;
  for (auto write :
       source.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
    if (write.getEffect() != schedule::ComputeEffectKind::Write &&
        write.getEffect() != schedule::ComputeEffectKind::Drive)
      continue;
    if (write.getResource() == schedule::ComputeResourceKind::Unknown ||
        write.getTarget() != schedule::ComputeTargetKind::Descriptor ||
        write.getDynamic() || !write.getWidth())
      return true;
    if (write.getResource() != watch.getResource() ||
        write.getDescriptor() != watch.getDescriptor())
      continue;
    uint64_t low = std::max(write.getLow(), watch.getLow());
    uint64_t high = std::min(write.getLow() + write.getWidth(),
                             watch.getLow() + watch.getWidth());
    if (low >= high)
      continue;
    matched = true;
    for (const auto &range : *ranges)
      if (low < range.low + range.width && range.low < high)
        return true;
  }
  return !matched;
}

std::optional<CombinationalFusionBody>
CombinationalFusionAnalysis::analyzeForReordering(
    sim::SimFuncOp function, const analysis::HandleDataflowAnalysis &provenance,
    CombinationalFusionFailure *failureReason) const {
  auto body = analyze(function, provenance, /*interleaved=*/true, failureReason,
                      /*finalValuesOnly=*/true);
  if (!body || !body->structured)
    return std::nullopt;
  const auto &memory = body->structured->getMemory();
  // analyze() has proved that every incoming output cell used on a path is
  // copied back unchanged on that path. Thus an extra union-watch activation
  // with unchanged inputs cannot advance retained state.
  // getActivationSliceOrder keeps every retained-state activation whole,
  // including later publications that could change its enable through another
  // process. Idempotence only certifies unchanged-input reruns; it does not
  // authorize moving a capture after those publications. The closed observer
  // certificate below still excludes observable intermediate values.
  if (!memory.hasValueDependencies()) {
    if (failureReason)
      *failureReason = {
          CombinationalFusionFailure::Reason::IncomingOutputState};
    return std::nullopt;
  }
  if (!canReorder({function}, failureReason))
    return std::nullopt;
  return body;
}

const CombinationalFusionAnalysis::InterleaveIndex &
CombinationalFusionAnalysis::getInterleaveIndex() const {
  if (interleaveIndex)
    return *interleaveIndex;
  InterleaveIndex &index = interleaveIndex.emplace();
  auto design = this->design;
  for (auto storage : design.getOps<sim::SimStorageDeclOp>())
    if (sim::hasTransitionObservers(storage))
      index.toggleRoots.insert(static_cast<uint64_t>(storage.getId()));
  for (auto net : design.getOps<sim::SimNetDeclOp>())
    if (sim::hasTransitionObservers(net))
      if (auto root = analysis::ActivationMemoryAnalysis::getRoot(
              schedule::ComputeResourceKind::Net, net.getId()))
        index.toggleRoots.insert(*root);
  auto graph = design.getComputeGraphAttr();
  if (!graph)
    return index;
  for (Attribute raw : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::Watch)
        continue;
      if (effect.getResource() != schedule::ComputeResourceKind::Storage &&
          effect.getResource() != schedule::ComputeResourceKind::Net) {
        if (effect.getResource() == schedule::ComputeResourceKind::Unknown)
          index.unknownWatch = true;
        continue;
      }
      if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
          !effect.getWidth() ||
          effect.getLow() > UINT64_MAX - effect.getWidth()) {
        index.unresolvedWatch = true;
        continue;
      }
      auto root = analysis::ActivationMemoryAnalysis::getRoot(
          effect.getResource(), effect.getDescriptor());
      if (!root) {
        index.unresolvedWatch = true;
        continue;
      }
      auto ranges =
          getSchedulingWatchRanges(fragment.getFunction().getAttr(), effect);
      assert(ranges && "resolved source watch has a scheduling range");
      for (const auto &range : *ranges)
        index.watchers[*root].push_back(
            {fragment.getFunction().getAttr(), range});
    }
  }
  return index;
}

bool CombinationalFusionAnalysis::canInterleave(
    ArrayRef<sim::SimFuncOp> functions,
    CombinationalFusionFailure *failureReason) const {
  using Reason = CombinationalFusionFailure::Reason;
  if (failureReason)
    *failureReason = {};
  auto reject = [&](CombinationalFusionFailure reason) {
    if (failureReason)
      *failureReason = reason;
    return false;
  };
  if (unsupported)
    return reject({Reason::UnsupportedObservations});
  DenseSet<StringAttr> owners;
  ActivationRanges repeated;
  for (auto function : functions) {
    auto found = activations.find(function);
    if (found == activations.end() || !found->second->isValid())
      return reject({Reason::MissingActivationProof});
    owners.insert(function.getSymNameAttr());
    llvm::append_range(repeated,
                       found->second->getMemory().getRepeatedWrites());
  }
  const InterleaveIndex &index = getInterleaveIndex();
  for (const auto &range : repeated)
    if (index.toggleRoots.contains(range.root))
      return reject({Reason::ToggleCoverage, {}, range.root});
  if (!repeated.empty() && index.unknownWatch)
    return reject({Reason::UnknownWatchedResource});
  if (index.unresolvedWatch)
    return reject({Reason::UnresolvedWatchedStorage});
  // IEEE 1800-2023 4.5-4.7 permits a nonpreempted source-ordered
  // activation. Its final values are idempotent, but repeated stores can
  // still produce transitions on an unchanged-input execution. No outside
  // wait may observe those extra transitions. Inside the cohort all
  // consumers execute after their producers' complete regions and fully
  // internal watches are removed. The materializer subtracts the cohort's
  // definite writes and builds exact reference views for the remaining
  // external sensitivity, so a mixed internal/external aggregate never
  // retains a self-watch.
  for (const auto &range : repeated) {
    auto found = index.watchers.find(range.root);
    if (found == index.watchers.end())
      continue;
    for (const auto &[owner, watch] : found->second)
      if (!owners.contains(owner) && activationRangesOverlap(range, watch))
        return reject({Reason::OutsideWatch, {}, watch.root, owner});
  }
  return true;
}

bool CombinationalFusionAnalysis::canReorder(
    ArrayRef<sim::SimFuncOp> functions,
    CombinationalFusionFailure *failureReason) const {
  using Reason = CombinationalFusionFailure::Reason;
  if (failureReason)
    *failureReason = {};
  auto reject = [&](CombinationalFusionFailure reason) {
    if (failureReason)
      *failureReason = reason;
    return false;
  };
  auto design = this->design;
  auto graph = design.getComputeGraphAttr();
  if (unsupported || !graph || graph.getVpi() != schedule::ComputeVPIMode::Off)
    return reject({Reason::UnsupportedObservations});
  DenseSet<StringAttr> owners;
  ActivationRanges writes;
  for (auto function : functions) {
    auto found = activations.find(function);
    if (found == activations.end() || !found->second->isValid())
      return reject({Reason::MissingActivationProof});
    owners.insert(function.getSymNameAttr());
    llvm::append_range(writes, found->second->getMemory().getMayWrites());
  }
  // A reference execution may publish intermediate values of every write.
  // They must stay invisible to every observer (9.4.2 waits, 4.10 callbacks,
  // 10.6 force, 21.7 dumps, toggle coverage) except side-effect-free
  // combinational processes, which only republish their own transitions.
  const auto &insensitive = getGlitchInsensitiveStorage();
  for (const auto &write : writes)
    if (!insensitive.contains(write.root))
      return reject({Reason::ObservableState,
                     {},
                     write.root,
                     glitchObservers.lookup(write.root)});
  return true;
}

const DenseSet<uint64_t> &
CombinationalFusionAnalysis::getGlitchInsensitiveStorage() const {
  if (glitchInsensitive)
    return *glitchInsensitive;
  glitchInsensitive.emplace();
  auto &result = *glitchInsensitive;
  auto design = this->design;
  auto graph = design.getComputeGraphAttr();
  if (unsupported || !graph || graph.getVpi() != schedule::ComputeVPIMode::Off)
    return result;
  for (auto storage : design.getOps<sim::SimStorageDeclOp>()) {
    auto observability = storage.getObservability();
    if ((!observability ||
         *observability == schedule::ComputeObservabilityKind::Invisible) &&
        !sim::hasTransitionObservers(storage))
      result.insert(static_cast<uint64_t>(storage.getId()));
  }
  for (auto net : design.getOps<sim::SimNetDeclOp>()) {
    auto observability = net.getObservability();
    if ((!observability ||
         *observability == schedule::ComputeObservabilityKind::Invisible) &&
        !sim::hasTransitionObservers(net))
      if (auto root = analysis::ActivationMemoryAnalysis::getRoot(
              schedule::ComputeResourceKind::Net, net.getId()))
        result.insert(*root);
  }
  // Waiting processes per root; a wait on an unresolved resource could
  // observe any storage.
  DenseMap<uint64_t, SmallVector<StringAttr>> watchers;
  for (Attribute raw : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::Watch)
        continue;
      if (effect.getResource() == schedule::ComputeResourceKind::Unknown) {
        result.clear();
        return result;
      }
      if (effect.getResource() != schedule::ComputeResourceKind::Storage &&
          effect.getResource() != schedule::ComputeResourceKind::Net)
        continue;
      if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor) {
        result.clear();
        return result;
      }
      auto root = analysis::ActivationMemoryAnalysis::getRoot(
          effect.getResource(), effect.getDescriptor());
      if (!root) {
        result.clear();
        return result;
      }
      auto ranges =
          getSchedulingWatchRanges(fragment.getFunction().getAttr(), effect);
      if (!ranges || !ranges->empty())
        watchers[*root].push_back(fragment.getFunction().getAttr());
    }
  }
  prepareActivations();
  // A transparent watcher reaches an idempotent state on watched inputs.
  // Its intermediate publications may depend on overwritten old output lanes,
  // but every output must remain inside this same transition-insensitive
  // closure. This weaker contract never admits an ordinary fusion by itself.
  SymbolTable symbols(design);
  DenseMap<StringAttr, std::optional<SmallVector<uint64_t>>> transparent;
  auto writesOf = [&](StringAttr owner) -> const auto & {
    auto [found, inserted] = transparent.try_emplace(owner);
    if (inserted) {
      auto function = symbols.lookup<sim::SimFuncOp>(owner);
      if (function && analyze(function, *provenance, /*interleaved=*/true,
                              nullptr, /*finalValuesOnly=*/true)) {
        SmallVector<uint64_t> roots;
        for (const auto &write :
             activations.at(function)->getMemory().getMayWrites())
          roots.push_back(write.root);
        found->second = std::move(roots);
      }
    }
    return found->second;
  };
  for (bool changed = true; changed;) {
    changed = false;
    for (uint64_t root : llvm::to_vector(result)) {
      for (StringAttr owner : watchers.lookup(root)) {
        const auto &roots = writesOf(owner);
        std::optional<uint64_t> exposed;
        if (roots)
          for (uint64_t written : *roots)
            if (!result.contains(written)) {
              exposed = written;
              break;
            }
        if (roots && !exposed)
          continue;
        // Remember the first opaque observer along the propagation path.
        glitchObservers[root] =
            exposed ? glitchObservers.lookup(*exposed) : owner;
        result.erase(root);
        changed = true;
        break;
      }
    }
  }
  return result;
}

bool isComputeBodyFusionEligible(
    sim::SimFuncOp function,
    const analysis::HandleDataflowAnalysis &provenance) {
  llvm::DenseMap<Operation *, bool> cache;
  llvm::SmallPtrSet<Operation *, 8> active;
  return isComputeBodyFusionEligibleImpl(function, provenance, cache, active,
                                         false);
}

bool isPrimitiveComputeBodyFusionEligible(
    sim::SimFuncOp function,
    const analysis::HandleDataflowAnalysis &provenance) {
  llvm::DenseMap<Operation *, bool> cache;
  llvm::SmallPtrSet<Operation *, 8> active;
  return isComputeBodyFusionEligibleImpl(function, provenance, cache, active,
                                         true);
}

SmallVector<uint32_t>
getComputeFusionReadyTargets(schedule::ComputeGraphAttr graph,
                             schedule::ComputeEffectAttr sensitivity) {
  SmallVector<uint32_t> targets;
  ArrayAttr nodes = graph.getNodes();

  // Sensitivity and NBA-activation edges enumerate every statically known
  // producer for a watched descriptor range. A delayed continuation may be
  // omitted from the co-ready set only when it is the graph's sole producer:
  // in that case it must be the fragment currently publishing the transition.
  // With multiple possible producers the deadline can be independently ready
  // and must remain an ordering barrier.
  llvm::SmallDenseSet<uint32_t> producers;
  for (Attribute attribute : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(attribute);
    if ((edge.getKind() == schedule::ComputeEdgeKind::Sensitivity ||
         edge.getKind() == schedule::ComputeEdgeKind::NBAActivate) &&
        edge.getResource() && rangesOverlap(edge.getResource(), sensitivity))
      producers.insert(edge.getSource());
  }
  std::optional<uint32_t> uniqueProducer;
  if (producers.size() == 1)
    uniqueProducer = *producers.begin();

  for (Attribute attribute : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(attribute);
    if (edge.getKind() != schedule::ComputeEdgeKind::Resume ||
        edge.getSource() >= nodes.size() || edge.getTarget() >= nodes.size())
      continue;
    auto source =
        dyn_cast<schedule::ComputeFragmentAttr>(nodes[edge.getSource()]);
    auto target =
        dyn_cast<schedule::ComputeFragmentAttr>(nodes[edge.getTarget()]);
    if (!source || !target)
      continue;
    if (source.getAction() == schedule::ComputeActionKind::SuspendDelay &&
        uniqueProducer == edge.getTarget())
      continue;
    targets.push_back(edge.getTarget());
  }
  return targets;
}

namespace {

bool overlaps(schedule::ComputeEffectAttr a, schedule::ComputeEffectAttr b) {
  if (a.getResource() != b.getResource() ||
      a.getDescriptor() != b.getDescriptor())
    return false;
  if (a.getDynamic() || b.getDynamic() || !a.getWidth() || !b.getWidth())
    return true;
  return a.getLow() < b.getLow() + b.getWidth() &&
         b.getLow() < a.getLow() + a.getWidth();
}

bool covers(schedule::ComputeEffectAttr watch,
            schedule::ComputeEffectAttr read) {
  return watch.getResource() == read.getResource() &&
         watch.getDescriptor() == read.getDescriptor() && !watch.getDynamic() &&
         watch.getLow() <= read.getLow() &&
         read.getLow() + read.getWidth() <= watch.getLow() + watch.getWidth();
}

std::optional<unsigned>
maxCountOnPaths(Block *from, Block *until, unsigned cap,
                llvm::function_ref<bool(Operation *)> counted);

/// An extra activation of `function` after the NBA region is unobservable
/// when it recomputes exactly the values it already holds. That needs a
/// looping process with one change-only wait; every read watched, so a wake
/// that changes no watched value sees the inputs of its previous activation;
/// no write it reads back; exclusive stored outputs; and a first activation
/// before the first wait, so the outputs are current from time zero. Bits it
/// may assign twice in one activation are returned in `glitches`; the caller
/// proves that nothing can observe them.
bool isIdempotentObserver(
    sim::SimFuncOp function, const analysis::HandleDataflowAnalysis &handles,
    const llvm::DenseMap<
        uint64_t,
        SmallVector<std::pair<Operation *, schedule::ComputeEffectAttr>>>
        &storageWriters,
    SmallVectorImpl<analysis::HandleFact> &glitches) {
  if (function.isExternal() ||
      function.getEntryKind() == sim::EntryKind::Observer ||
      function.getHomeRegion() != sim::EventRegion::Active)
    return false;
  ArrayAttr summary = function.getEffectSummaryAttr();
  if (!summary)
    return false;
  Operation *suspension = nullptr;
  bool valid = true;
  function.walk([&](Operation *op) {
    if (op == function.getOperation() || !valid)
      return;
    if (sim::isSuspensionOp(op)) {
      auto any = dyn_cast<sim::SimSuspendAnyOp>(op);
      valid = !suspension &&
              (isa<sim::SimSuspendChangeOp>(op) ||
               (any && llvm::all_of(any.getEdges(), [](int32_t edge) {
                  return edge == static_cast<int32_t>(sim::EdgeKind::Change);
                })));
      suspension = op;
      return;
    }
    if (isa<sim::SimRefLoadOp, sim::SimNetReadOp, sim::SimRefStoreOp,
            sim::SimDriverDriveOp, sim::SimDriverDriveChangedOp, cf::BranchOp,
            cf::CondBranchOp>(op))
      return;
    valid = op->getNumRegions() == 0 && isMemoryEffectFree(op);
  });
  if (!valid || !suspension || suspension->getNumSuccessors() != 1)
    return false;
  if (auto region =
          TypeSwitch<Operation *, sim::EventRegionAttr>(suspension)
              .Case<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(
                  [](auto wait) { return wait.getResumeRegionAttr(); })
              .Default(sim::EventRegionAttr{});
      region && region.getValue() != sim::EventRegion::Active)
    return false;
  // Every path from entry to the wait must first run the activation, unless
  // the process is evaluated at time zero by definition: continuous
  // assignments, including those inferred from ports (LRM 4.9.1).
  // A process that writes nothing cannot be out of date either.
  Block *activation = suspension->getSuccessor(0);
  Block *wait = suspension->getBlock();
  bool writesAnything = llvm::any_of(
      summary.getAsRange<schedule::ComputeEffectAttr>(),
      [](schedule::ComputeEffectAttr effect) {
        return effect.getEffect() != schedule::ComputeEffectKind::Read &&
               effect.getEffect() != schedule::ComputeEffectKind::Watch;
      });
  bool evaluatedAtTimeZero =
      !writesAnything ||
      function.getEntryKind() == sim::EntryKind::Continuous ||
      function.getEntryKind() == sim::EntryKind::PortInput ||
      function.getEntryKind() == sim::EntryKind::PortOutput;
  SmallVector<Block *> pending;
  if (!evaluatedAtTimeZero)
    pending.push_back(&function.getBody().front());
  llvm::SmallPtrSet<Block *, 16> visited;
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    if (block == activation || !visited.insert(block).second)
      continue;
    if (block == wait)
      return false;
    llvm::append_range(pending, block->getSuccessors());
  }
  // The activation must return to the same wait on every path.
  pending.assign({activation});
  visited.clear();
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    if (block == wait || !visited.insert(block).second)
      continue;
    if (block->getNumSuccessors() == 0)
      return false;
    llvm::append_range(pending, block->getSuccessors());
  }

  SmallVector<schedule::ComputeEffectAttr> reads, watches, writes;
  for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
    if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
        effect.getDeferred())
      return false;
    switch (effect.getEffect()) {
    case schedule::ComputeEffectKind::Read:
      reads.push_back(effect);
      break;
    case schedule::ComputeEffectKind::Watch:
      if (effect.getDynamic() ||
          (effect.getTrigger() != schedule::ComputeTriggerKind::None &&
           effect.getTrigger() != schedule::ComputeTriggerKind::Change))
        return false;
      watches.push_back(effect);
      break;
    case schedule::ComputeEffectKind::Write:
    case schedule::ComputeEffectKind::Drive:
      if (effect.getDynamic())
        return false;
      writes.push_back(effect);
      break;
    default:
      return false;
    }
  }
  for (schedule::ComputeEffectAttr read : reads)
    if (!llvm::any_of(watches, [&](schedule::ComputeEffectAttr watch) {
          return covers(watch, read);
        }))
      return false;
  for (schedule::ComputeEffectAttr write : writes) {
    if (llvm::any_of(reads, [&](schedule::ComputeEffectAttr read) {
          return overlaps(write, read);
        }))
      return false;
    // A driver belongs to this process. A stored output must not be
    // replaced by another writer between two activations.
    if (write.getEffect() != schedule::ComputeEffectKind::Write)
      continue;
    auto others = storageWriters.find(write.getDescriptor());
    if (others != storageWriters.end())
      for (auto [owner, effect] : others->second)
        if (owner != function.getOperation() && overlaps(write, effect))
          return false;
  }
  // Assigning the value an object already holds is no change in state, so
  // it is no update event (IEEE 1800-2023 4.3). A second assignment of the
  // same bits in one activation, as in `y = 0; if (c) y = 1;`, passes
  // through another value even when the inputs are unchanged: y goes 1 -> 0
  // -> 1, and the 0 -> 1 update is a posedge (9.4.2, Table 9-2). Such an
  // update schedules every process sensitive to y (4.5), so dropping the
  // activation drops events those processes see. Report every range that may
  // be assigned twice; the caller admits it only if nothing can observe it.
  // A write without a precise target is rejected here. Writes reach state
  // only through the stores and drives admitted above.
  // Count per written range rather than per summary effect, which merges
  // disjoint selects of one variable into a single range.
  analysis::HandleFacts facts = handles.derive(function);
  auto writtenTarget = [&](Operation *operation) -> std::optional<Value> {
    if (auto store = dyn_cast<sim::SimRefStoreOp>(operation))
      return store.getReference();
    if (auto drive = dyn_cast<sim::SimDriverDriveOp>(operation))
      return drive.getDriver();
    if (auto drive = dyn_cast<sim::SimDriverDriveChangedOp>(operation))
      return drive.getDriver();
    return std::nullopt;
  };
  auto mayOverlap = [&](Value lhs, Value rhs) {
    auto left = facts.find(lhs), right = facts.find(rhs);
    if (left == facts.end() || right == facts.end() ||
        !left->second.descriptor || !right->second.descriptor)
      return true;
    const analysis::HandleFact &a = left->second, &b = right->second;
    if (a.resource != b.resource || *a.descriptor != *b.descriptor)
      return false;
    if (a.dynamic || b.dynamic || !a.width || !b.width)
      return true;
    return a.low < b.low + b.width && b.low < a.low + a.width;
  };
  // Count once per distinct target range; many stores share one.
  SmallVector<Value> targets;
  std::set<std::tuple<bool, int, uint64_t, uint64_t, uint64_t, bool>> seen;
  function.walk([&](Operation *operation) {
    std::optional<Value> target = writtenTarget(operation);
    if (!target)
      return;
    auto found = facts.find(*target);
    bool known = found != facts.end() && found->second.descriptor;
    const analysis::HandleFact fact =
        known ? found->second : analysis::HandleFact{};
    if (seen.insert({known, static_cast<int>(fact.resource),
                     known ? *fact.descriptor : 0, fact.low, fact.width,
                     fact.dynamic})
            .second)
      targets.push_back(*target);
  });
  for (Value target : targets) {
    std::optional<unsigned> count = maxCountOnPaths(
        activation, wait, /*cap=*/1, [&](Operation *operation) {
          std::optional<Value> other = writtenTarget(operation);
          return other && mayOverlap(target, *other);
        });
    if (count && *count <= 1)
      continue;
    auto found = facts.find(target);
    if (found == facts.end() || !found->second.descriptor)
      return false;
    glitches.push_back(found->second);
  }
  return true;
}

/// Dense finite execution bounds over the activation CFG. The lattice is
/// unreachable < 0 < ... < cap < many. Saturation makes cyclic CFGs converge;
/// a loop without writes does not invalidate an otherwise bounded proof.
/// `until` ends this activation, not an NBA window (LRM 4.4, 10.4.2).
std::optional<unsigned>
maxCountOnPaths(Block *from, Block *until, unsigned cap,
                llvm::function_ref<bool(Operation *)> counted) {
  const unsigned many = cap + 1;
  DenseMap<Block *, unsigned> costs;
  SmallVector<Block *> discover{from};
  while (!discover.empty()) {
    Block *block = discover.pop_back_val();
    if (costs.contains(block))
      continue;
    unsigned cost = 0;
    for (Operation &op : *block) {
      if (counted(&op))
        cost = std::min(many, cost + 1);
      else if (op.getNumRegions() != 0 &&
               op.walk([&](Operation *nested) {
                   return counted(nested) ? WalkResult::interrupt()
                                          : WalkResult::advance();
                 }).wasInterrupted())
        return std::nullopt;
    }
    costs[block] = cost;
    if (block != until)
      llvm::append_range(discover, block->getSuccessors());
  }
  DenseMap<Block *, unsigned> incoming;
  incoming[from] = 0;
  SmallVector<Block *> pending{from};
  DenseSet<Block *> queued{from};
  unsigned best = 0;
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    queued.erase(block);
    unsigned count =
        std::min(many, incoming.lookup(block) + costs.lookup(block));
    best = std::max(best, count);
    if (best == many)
      return many;
    if (block == until)
      continue;
    for (Block *successor : block->getSuccessors()) {
      auto [found, inserted] = incoming.try_emplace(successor, count);
      if (!inserted && count <= found->second)
        continue;
      found->second = count;
      if (queued.insert(successor).second)
        pending.push_back(successor);
    }
  }
  return best;
}

/// The single suspension of a looping process, or null.
Operation *singleSuspension(sim::SimFuncOp function) {
  Operation *suspension = nullptr;
  bool unique = true;
  function.walk([&](Operation *op) {
    if (!sim::isSuspensionOp(op))
      return;
    unique &= suspension == nullptr;
    suspension = op;
  });
  return unique && suspension && suspension->getNumSuccessors() == 1
             ? suspension
             : nullptr;
}

} // namespace

std::optional<NBATransientObservers>
computeNBATransientObservers(sim::SimDesignOp design, bool guardedVPI) {
  schedule::ComputeGraphAttr graph = design.getComputeGraphAttr();
  // VPI value-change callbacks run at each update.
  if (!graph ||
      (!guardedVPI && graph.getVpi() != schedule::ComputeVPIMode::Off))
    return std::nullopt;
  llvm::DenseMap<
      uint64_t,
      SmallVector<std::pair<Operation *, schedule::ComputeEffectAttr>>>
      storageWriters;
  SmallVector<sim::SimFuncOp> functions;
  bool complete = true;
  // Proofs that remove a root from `changeWatched` or skip an observer need
  // every writer of a root. A write through a formal is attributed to the
  // actuals its call sites pass (IEEE 1800-2023 13.5: output and inout
  // actuals are written on return, ref actuals directly). A write that cannot
  // be resolved leaves the inventory incomplete; that disables those proofs,
  // not the whole analysis.
  bool writersComplete = true;
  analysis::HandleDataflowAnalysis provenanceAnalysis(design);
  FormalWriteResolver formals(design, provenanceAnalysis);
  design.walk([&](sim::SimFuncOp function) {
    functions.push_back(function);
    ArrayAttr summary = function.getEffectSummaryAttr();
    if (!summary) {
      // A body without a summary may still wait on storage.
      complete &=
          function.isExternal() || !function
                                        .walk([](Operation *op) {
                                          return sim::isSuspensionOp(op)
                                                     ? WalkResult::interrupt()
                                                     : WalkResult::advance();
                                        })
                                        .wasInterrupted();
      return;
    }
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::Write &&
          effect.getEffect() != schedule::ComputeEffectKind::NBA)
        continue;
      // A write through an unresolved handle can reach any storage root.
      if (effect.getResource() == schedule::ComputeResourceKind::Unknown)
        writersComplete = false;
      if (effect.getResource() == schedule::ComputeResourceKind::Storage) {
        if (effect.getTarget() == schedule::ComputeTargetKind::Formal) {
          writersComplete &= formals.resolve(
              function.getSymNameAttr(), effect,
              [&](uint64_t descriptor, schedule::ComputeEffectAttr write) {
                storageWriters[descriptor].push_back(
                    {function.getOperation(), write});
              });
          continue;
        }
        if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor) {
          writersComplete = false;
          continue;
        }
        storageWriters[effect.getDescriptor()].push_back(
            {function.getOperation(), effect});
      }
    }
  });
  complete &= !analysis::DPIEffectAnalysis(design).anyCallMayAccessDesign();
  if (!complete)
    return std::nullopt;

  NBATransientObservers result;
  // IEEE 1800-2023 4.9.3, 4.9.4, 6.8: declaration initialization cannot
  // intervene between an NBA capture and its commit. Called tasks/functions
  // are already instantiated into each process summary. Preserve this source
  // inventory before fusion introduces private references and loses precision.
  llvm::DenseSet<uint64_t> immediateWriters;
  bool immediateComplete = true;
  for (sim::SimFuncOp function : functions) {
    if (function.getEntryKind() == sim::EntryKind::RootInitializer ||
        function.getEntryKind() == sim::EntryKind::Function ||
        function.getEntryKind() == sim::EntryKind::Task)
      continue;
    auto summary = function.getEffectSummaryAttr();
    if (!summary) {
      immediateComplete = false;
      continue;
    }
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::Write &&
          effect.getEffect() != schedule::ComputeEffectKind::Drive)
        continue;
      if (effect.getResource() == schedule::ComputeResourceKind::Unknown)
        immediateComplete = false;
      else if (effect.getResource() == schedule::ComputeResourceKind::Storage) {
        if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor)
          immediateComplete = false;
        else {
          immediateWriters.insert(effect.getDescriptor());
        }
      }
    }
  }
  // Inspect callees too: instantiated summaries may omit an opaque mutation
  // in a task body. Such a mutation invalidates the whole writer certificate.
  design.walk([&](sim::SimFuncOp function) {
    if (function.getEntryKind() == sim::EntryKind::RootInitializer)
      return;
    function.walk([&](Operation *operation) {
      if (isa<sim::SimCallOp, sim::SimTaskCallOp, sim::SimRefStoreOp,
              sim::SimRefAllocOp, sim::SimNBAEnqueueOp>(operation))
        return;
      if (auto effects = dyn_cast<MemoryEffectOpInterface>(operation)) {
        SmallVector<MemoryEffects::EffectInstance> instances;
        effects.getEffects(instances);
        for (const auto &effect : instances)
          if (isa<MemoryEffects::Write>(effect.getEffect()) &&
              isa<sim::StorageResource>(effect.getResource()))
            immediateComplete = false;
      }
    });
  });
  if (immediateComplete) {
    result.immediateWriters = std::move(immediateWriters);
  }
  llvm::DenseSet<uint64_t> &observable = result.observable;
  design.walk([&](sim::SimStorageDeclOp storage) {
    if (sim::hasTransitionObservers(storage))
      observable.insert(storage.getId());
  });
  // Who can see an intermediate value of a process's own writes. An update
  // schedules evaluation events only for processes sensitive to it (IEEE
  // 1800-2023 4.3, 4.5), and a process may run without suspension (4.7), so
  // any other process reads the value before or after that activation. The
  // remaining observers are sensitive processes and toggle coverage
  // (recorded with no watcher). Value-change callbacks (38.36.1) may exist
  // under a VPI guard, so nothing is unobservable there. The VCD writer
  // (21.7) compares state once per time slot and so records no intermediate
  // value.
  using WatchKey = std::pair<unsigned, uint64_t>;
  struct WatchRange {
    uint64_t low, width;
    Operation *watcher;
  };
  llvm::DenseMap<WatchKey, SmallVector<WatchRange>> watchedRanges;
  bool everythingObservable =
      guardedVPI && graph.getVpi() != schedule::ComputeVPIMode::Off;
  auto watchWhole = [&](schedule::ComputeResourceKind resource,
                        uint64_t descriptor, Operation *watcher) {
    watchedRanges[{static_cast<unsigned>(resource), descriptor}].push_back(
        {0, UINT64_MAX, watcher});
  };
  design.walk([&](Operation *operation) {
    if (auto storage = dyn_cast<sim::SimStorageDeclOp>(operation)) {
      if (sim::hasTransitionObservers(storage))
        watchWhole(schedule::ComputeResourceKind::Storage, storage.getId(),
                   nullptr);
    } else if (auto net = dyn_cast<sim::SimNetDeclOp>(operation)) {
      if (sim::hasTransitionObservers(net))
        watchWhole(schedule::ComputeResourceKind::Net, net.getId(), nullptr);
    }
  });
  for (sim::SimFuncOp function : functions)
    if (ArrayAttr summary = function.getEffectSummaryAttr())
      for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
        if (effect.getEffect() != schedule::ComputeEffectKind::Watch)
          continue;
        // A named event carries no value (15.5); only an unresolved watch
        // can reach any variable.
        if (effect.getResource() == schedule::ComputeResourceKind::Event)
          continue;
        if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
            (effect.getResource() != schedule::ComputeResourceKind::Storage &&
             effect.getResource() != schedule::ComputeResourceKind::Net)) {
          everythingObservable = true;
          continue;
        }
        if (effect.getDynamic() || !effect.getWidth())
          watchWhole(effect.getResource(), effect.getDescriptor(), function);
        else
          watchedRanges[{static_cast<unsigned>(effect.getResource()),
                         effect.getDescriptor()}]
              .push_back({effect.getLow(), effect.getWidth(), function});
      }
  // A glitch is invisible when every process sensitive to it is itself an
  // admitted idempotent observer: run after the glitching activation with
  // its unchanged final inputs (an order 4.5 and 4.7 permit), it assigns
  // only the values it holds, which is no update event (4.3), or glitches
  // that are invisible in turn. Admit observers as a least fixpoint, so every
  // admission rests on a finite chain. Observers that glitch each other are
  // never admitted.
  struct Observer {
    Operation *function;
    SmallVector<analysis::HandleFact> glitches;
  };
  SmallVector<Observer> observers;
  if (writersComplete)
    for (sim::SimFuncOp function : functions) {
      ArrayAttr summary = function.getEffectSummaryAttr();
      if (!summary || llvm::none_of(summary.getAsRange<
                                        schedule::ComputeEffectAttr>(),
                                    [](schedule::ComputeEffectAttr effect) {
                                      return effect.getEffect() ==
                                             schedule::ComputeEffectKind::Watch;
                                    }))
        continue;
      Observer observer{function, {}};
      if (isIdempotentObserver(function, provenanceAnalysis, storageWriters,
                               observer.glitches))
        observers.push_back(std::move(observer));
    }
  llvm::DenseSet<Operation *> idempotent;
  auto invisible = [&](const analysis::HandleFact &write) {
    // A drive updates a resolved net and every net connected to it (23.3.3.7,
    // 28.8), which this index does not follow; keep repeated drives visible.
    if (everythingObservable ||
        write.resource != schedule::ComputeResourceKind::Storage)
      return false;
    auto found = watchedRanges.find(
        {static_cast<unsigned>(write.resource), *write.descriptor});
    if (found == watchedRanges.end())
      return true;
    bool whole = write.dynamic || !write.width;
    return llvm::all_of(found->second, [&](const WatchRange &range) {
      bool overlap = whole || range.width == UINT64_MAX ||
                     (range.low < write.low + write.width &&
                      write.low < range.low + range.width);
      return !overlap ||
             (range.watcher && idempotent.contains(range.watcher));
    });
  };
  SmallVector<const Observer *> pending;
  for (const Observer &observer : observers) {
    if (observer.glitches.empty())
      idempotent.insert(observer.function);
    else
      pending.push_back(&observer);
  }
  for (bool changed = true; changed;) {
    changed = false;
    llvm::erase_if(pending, [&](const Observer *observer) {
      if (!llvm::all_of(observer->glitches, invisible))
        return false;
      idempotent.insert(observer->function);
      changed = true;
      return true;
    });
  }
  for (sim::SimFuncOp function : functions) {
    ArrayAttr summary = function.getEffectSummaryAttr();
    if (!summary)
      continue;
    // An iff guard observes its inputs when another root's event occurs,
    // even if changes of the guard alone do not wake this process. Its reads
    // therefore constrain cross-root NBA publication order just like the
    // watched clock (IEEE 1800-2023 4.6(b), 9.4.2.3). A layout-ordered merge
    // of the guard ahead of a queued clock would sample the wrong value.
    bool conditionalWatch =
        function
            .walk([](Operation *operation) {
              return isa<sim::SimSuspendEdgeIffOp, sim::SimSuspendClockSetOp,
                         sim::SimSuspendLevelOp, sim::SimSuspendObserveOp>(
                         operation)
                         ? WalkResult::interrupt()
                         : WalkResult::advance();
            })
            .wasInterrupted();
    if (conditionalWatch)
      for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
        if (effect.getEffect() != schedule::ComputeEffectKind::Read)
          continue;
        if (effect.getResource() == schedule::ComputeResourceKind::Storage &&
            effect.getTarget() == schedule::ComputeTargetKind::Descriptor)
          observable.insert(effect.getDescriptor());
        else if (effect.getResource() == schedule::ComputeResourceKind::Net &&
                 effect.getTarget() == schedule::ComputeTargetKind::Descriptor)
          result.netObservable.insert(effect.getDescriptor());
        else if (effect.getResource() == schedule::ComputeResourceKind::Unknown ||
                 effect.getTarget() != schedule::ComputeTargetKind::Descriptor)
          return std::nullopt;
      }
    SmallVector<schedule::ComputeEffectAttr> watches;
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>())
      if (effect.getEffect() == schedule::ComputeEffectKind::Watch)
        watches.push_back(effect);
    if (watches.empty() || idempotent.contains(function))
      continue;
    // A process that waits only for a change of whole references wakes when
    // any update changes a watched bit. A merged commit reproduces exactly
    // that if it also reports bits rewritten with a different value in one
    // barrier, so such a watch needs a transient mask, not ordered commits.
    // Edge, level, conditional and expression waits see the value sequence.
    bool changeWaitsOnly =
        function.getEntryKind() != sim::EntryKind::Observer &&
        !function
             .walk([](Operation *op) {
               if (!sim::isSuspensionOp(op) ||
                   isa<sim::SimSuspendChangeOp, sim::SimSuspendDelayOp>(op))
                 return WalkResult::advance();
               auto any = dyn_cast<sim::SimSuspendAnyOp>(op);
               bool change =
                   any && llvm::all_of(any.getEdges(), [](int32_t edge) {
                     return edge == static_cast<int32_t>(sim::EdgeKind::Change);
                   });
               return change ? WalkResult::advance() : WalkResult::interrupt();
             })
             .wasInterrupted();
    for (schedule::ComputeEffectAttr watch : watches) {
      // A watch through a subroutine formal or an unresolved handle can
      // reach any root.
      if (watch.getTarget() != schedule::ComputeTargetKind::Descriptor)
        return std::nullopt;
      bool changeWatch =
          changeWaitsOnly &&
          (watch.getTrigger() == schedule::ComputeTriggerKind::None ||
           watch.getTrigger() == schedule::ComputeTriggerKind::Change);
      if (watch.getResource() == schedule::ComputeResourceKind::Net) {
        if (!changeWatch)
          result.netObservable.insert(watch.getDescriptor());
        continue;
      }
      if (watch.getResource() != schedule::ComputeResourceKind::Storage)
        continue;
      // A dynamic watch wakes on a change anywhere in its root, which the
      // commit's per-bit change report covers as well.
      (changeWatch ? result.changeWatched : observable)
          .insert(watch.getDescriptor());
    }
  }
  for (uint64_t descriptor : observable)
    result.changeWatched.erase(descriptor);

  // A change-watched root that receives at most one NBA per bit in any time
  // slot has no round trip to report, so it needs no transient mask. Prove it
  // on source processes: one writer process, at most one write per activation
  // path, activated only by an edge of a clock that changes at most once per
  // slot (its sole writer toggles it after each positive delay).
  llvm::DenseMap<uint64_t, SmallVector<sim::SimFuncOp>> netDrivers;
  for (sim::SimFuncOp function : functions)
    if (ArrayAttr summary = function.getEffectSummaryAttr())
      for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>())
        if (effect.getEffect() == schedule::ComputeEffectKind::Drive &&
            effect.getResource() == schedule::ComputeResourceKind::Net)
          netDrivers[effect.getDescriptor()].push_back(function);
  bool processControl = false;
  llvm::StringMap<unsigned> spawns;
  llvm::StringSet<> spawnedOutsideRoot, called, calledOutsideRoot;
  design.walk([&](Operation *op) {
    processControl |= isa<sim::SimProcessControlOp, sim::SimControlDisableOp,
                          sim::SimOverrideOp, sim::SimReleaseOverrideOp,
                          sim::SimDynamicOverrideOp>(op);
    if (auto spawn = dyn_cast<sim::SimSpawnOp>(op)) {
      ++spawns[spawn.getCallee()];
      auto owner = spawn->getParentOfType<sim::SimFuncOp>();
      if (!owner || owner.getEntryKind() != sim::EntryKind::RootInitializer ||
          spawn->getParentRegion() != &owner.getBody())
        spawnedOutsideRoot.insert(spawn.getCallee());
    } else if (isa<sim::SimCallOp, sim::SimTaskCallOp>(op)) {
      StringRef callee = isa<sim::SimCallOp>(op)
                             ? cast<sim::SimCallOp>(op).getCallee()
                             : cast<sim::SimTaskCallOp>(op).getCallee();
      called.insert(callee);
      auto owner = op->getParentOfType<sim::SimFuncOp>();
      if (!owner || owner.getEntryKind() != sim::EntryKind::RootInitializer)
        calledOutsideRoot.insert(callee);
    }
  });
  // Declaration initializers run from the root initializer. IEEE 1800-2017
  // 6.8 sets these values before any initial or always procedure starts, so
  // no wait exists yet to observe them.
  auto initializesOnly = [&](sim::SimFuncOp function) {
    if (function.getEntryKind() == sim::EntryKind::RootInitializer)
      return true;
    StringRef name = function.getSymName();
    return function.getEntryKind() == sim::EntryKind::Function &&
           called.contains(name) && !calledOutsideRoot.contains(name) &&
           !spawns.contains(name) &&
           !function
                .walk([](Operation *op) {
                  return sim::isSuspensionOp(op) ? WalkResult::interrupt()
                                                 : WalkResult::advance();
                })
                .wasInterrupted();
  };
  if (processControl || !writersComplete || result.changeWatched.empty())
    return result;
  auto singleInstance = [&](sim::SimFuncOp function) {
    StringRef name = function.getSymName();
    return spawns.lookup(name) == 1 && !spawnedOutsideRoot.contains(name) &&
           !called.contains(name);
  };
  llvm::DenseMap<Operation *, analysis::HandleFacts> provenance;
  using Resource = std::pair<schedule::ComputeResourceKind, uint64_t>;
  auto resourceOf = [&](sim::SimFuncOp function,
                        Value value) -> std::optional<Resource> {
    auto [entry, inserted] = provenance.try_emplace(function.getOperation());
    if (inserted)
      entry->second = provenanceAnalysis.derive(function);
    auto found = entry->second.find(value);
    if (found == entry->second.end() || !found->second.descriptor ||
        found->second.dynamic ||
        (found->second.resource != schedule::ComputeResourceKind::Storage &&
         found->second.resource != schedule::ComputeResourceKind::Net))
      return std::nullopt;
    return Resource{found->second.resource, *found->second.descriptor};
  };
  auto descriptorOf = [&](sim::SimFuncOp function,
                          Value value) -> std::optional<uint64_t> {
    std::optional<Resource> resource = resourceOf(function, value);
    if (!resource || resource->first != schedule::ComputeResourceKind::Storage)
      return std::nullopt;
    return resource->second;
  };
  // Every path through one activation writes `descriptor` at most `limit`
  // times, and the path from process start to the first wait at most
  // `startLimit` times.
  auto boundedWrites = [&](sim::SimFuncOp function, Operation *suspension,
                           uint64_t descriptor, unsigned limit,
                           unsigned startLimit,
                           llvm::function_ref<Value(Operation *)> target) {
    auto counted = [&](Operation *op) {
      Value destination = target(op);
      if (!destination)
        return false;
      std::optional<uint64_t> written = descriptorOf(function, destination);
      return !written || *written == descriptor;
    };
    Block *wait = suspension->getBlock();
    std::optional<unsigned> activation =
        maxCountOnPaths(suspension->getSuccessor(0), wait, limit, counted);
    std::optional<unsigned> start =
        maxCountOnPaths(&function.getBody().front(), wait, startLimit, counted);
    return activation && start && *activation <= limit && *start <= startLimit;
  };
  // The resource a copy process forwards to `written`, such as a port
  // connection: it waits for any change, reads one resource and writes
  // `written` once per activation, so `written` changes at most once per
  // change of that resource.
  auto copiedBy = [&](sim::SimFuncOp copy,
                      Resource written) -> std::optional<Resource> {
    Operation *wait = singleSuspension(copy);
    auto any = dyn_cast_or_null<sim::SimSuspendAnyOp>(wait);
    ArrayAttr summary = copy.getEffectSummaryAttr();
    if (!wait || !summary || !singleInstance(copy) ||
        !(isa<sim::SimSuspendChangeOp>(wait) ||
          (any && llvm::all_of(any.getEdges(), [](int32_t edge) {
             return edge == static_cast<int32_t>(sim::EdgeKind::Change);
           }))))
      return std::nullopt;
    std::optional<Resource> copied;
    for (auto effect : summary.getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
          effect.getDynamic())
        return std::nullopt;
      Resource resource{effect.getResource(), effect.getDescriptor()};
      switch (effect.getEffect()) {
      case schedule::ComputeEffectKind::Read:
      case schedule::ComputeEffectKind::Watch:
        if (copied && *copied != resource)
          return std::nullopt;
        copied = resource;
        break;
      case schedule::ComputeEffectKind::Drive:
      case schedule::ComputeEffectKind::Write:
        if (resource != written)
          return std::nullopt;
        break;
      default:
        return std::nullopt;
      }
    }
    unsigned writes = 0;
    copy.walk([&](Operation *op) {
      writes += isa<sim::SimDriverDriveOp, sim::SimDriverDriveChangedOp,
                    sim::SimRefStoreOp>(op);
    });
    if (writes > 1)
      return std::nullopt;
    return copied;
  };
  std::function<bool(Resource, unsigned)> freeRunningClock =
      [&](Resource source, unsigned depth) -> bool {
    if (depth > 8)
      return false;
    if (source.first == schedule::ComputeResourceKind::Net) {
      auto drivers = netDrivers.find(source.second);
      if (drivers == netDrivers.end() || drivers->second.size() != 1)
        return false;
      std::optional<Resource> copied =
          copiedBy(drivers->second.front(), source);
      return copied && freeRunningClock(*copied, depth + 1);
    }
    uint64_t clock = source.second;
    auto writers = storageWriters.find(clock);
    if (writers == storageWriters.end())
      return false;
    sim::SimFuncOp toggler;
    for (auto [owner, effect] : writers->second) {
      auto function = cast<sim::SimFuncOp>(owner);
      if (effect.getEffect() != schedule::ComputeEffectKind::Write)
        return false;
      if (initializesOnly(function))
        continue;
      if (toggler && toggler != function)
        return false;
      toggler = function;
    }
    if (!toggler || !singleInstance(toggler))
      return false;
    if (std::optional<Resource> copied = copiedBy(toggler, source))
      return freeRunningClock(*copied, depth + 1);
    auto delay =
        dyn_cast_or_null<sim::SimSuspendDelayOp>(singleSuspension(toggler));
    auto constant =
        delay ? delay.getDelay().getDefiningOp<sim::SimTimeConstantOp>()
              : sim::SimTimeConstantOp{};
    if (!constant || constant.getValue() == 0)
      return false;
    // No write before the first delay, so at time zero only declaration
    // initialization, which precedes every procedure (6.8), sets the clock.
    return boundedWrites(toggler, delay, clock, 1, 0, [](Operation *op) {
      auto store = dyn_cast<sim::SimRefStoreOp>(op);
      return store ? store.getReference() : Value{};
    });
  };
  SmallVector<uint64_t> candidates(result.changeWatched.begin(),
                                   result.changeWatched.end());
  for (uint64_t root : candidates) {
    auto writers = storageWriters.find(root);
    if (writers == storageWriters.end())
      continue;
    sim::SimFuncOp process;
    bool single = true;
    for (auto [owner, effect] : writers->second) {
      if (effect.getEffect() != schedule::ComputeEffectKind::NBA)
        continue;
      auto function = cast<sim::SimFuncOp>(owner);
      single &= !process || process == function;
      process = function;
    }
    if (!single || !process || !singleInstance(process) ||
        (process.getEntryKind() != sim::EntryKind::Always &&
         process.getEntryKind() != sim::EntryKind::AlwaysFF))
      continue;
    auto edge =
        dyn_cast_or_null<sim::SimSuspendEdgeOp>(singleSuspension(process));
    if (!edge)
      continue;
    std::optional<Resource> clock = resourceOf(process, edge.getWatched());
    if (!clock ||
        (clock->first == schedule::ComputeResourceKind::Storage &&
         clock->second == root) ||
        !freeRunningClock(*clock, 0))
      continue;
    if (boundedWrites(process, edge, root, 1, 0, [](Operation *op) {
          auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(op);
          return enqueue ? enqueue.getDestination() : Value{};
        }))
      result.changeWatched.erase(root);
  }
  return result;
}

} // namespace talos
