//===- SimulationAOTEvalAnalysis.cpp - Resolve generated eval plan -------===//

#include "../SimulationToLLVMCoroutine/SimulationAOTPlanning.h"
#include "../SimulationToLLVMCoroutine/SimulationToLLVMCoroutinePrivate.h"
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Analysis/SimulationScheduleAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/Transforms/NativeTransforms.h"

#include "talos/Runtime/ActivationOrder.h"
#include "talos/Runtime/StableHandle.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SparseBitVector.h"
#include "llvm/ADT/StringMap.h"

#include <algorithm>
#include <map>
#include <numeric>

using namespace mlir;

namespace talos::detail {
namespace {

/// Change ready-bit identities before any executable tables or NBA taint masks
/// are emitted. Every owner-indexed fact must follow the same permutation.
void reorderOwners(ResolvedNativeEvalPlan &plan, ArrayRef<uint32_t> order) {
  assert(order.size() == plan.mergedFragments.size());
  assert(plan.recordNBATaintMasks.empty() && plan.nbaTaintedRecords.empty());
  SmallVector<uint32_t> remap(order.size());
  for (auto [rank, oldIndex] : llvm::enumerate(order))
    remap[oldIndex] = rank;
  auto reorder = [&](auto &values) {
    if (values.empty())
      return;
    assert(values.size() == order.size());
    auto old = std::move(values);
    values.clear();
    values.reserve(order.size());
    for (uint32_t index : order)
      values.push_back(std::move(old[index]));
  };
  reorder(plan.mergedFragments);
  reorder(plan.mergedExecutors);
  reorder(plan.mergedTwoStateExecutors);
  reorder(plan.mergedPromotionRanges);
  reorder(plan.ownerSubsumptionMasks);
  reorder(plan.deferredOwners);
  for (auto [rank, fragment] : llvm::enumerate(plan.mergedFragments))
    fragment.bit = rank;
  for (auto &mask : plan.ownerSubsumptionMasks) {
    APInt mapped(mask.getBitWidth(), 0);
    while (!mask.isZero()) {
      unsigned bit = mask.countr_zero();
      mapped.setBit(remap[bit]);
      mask.clearBit(bit);
    }
    mask = std::move(mapped);
  }
  for (auto &entry : plan.fanoutEntries)
    if ((entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK) ==
        TALOS_RT_FANOUT_DIRECT)
      entry.merged_bit = remap[entry.merged_bit];
  for (uint32_t &bit : plan.periodicOwnerBits)
    if (bit != UINT32_MAX)
      bit = remap[bit];
  for (auto *records :
       {&plan.periodicClosureRecords, &plan.periodicEntryRecords}) {
    for (unsigned &record : *records)
      record = remap[record];
    llvm::sort(*records);
  }
  for (auto &node : plan.rankedNodes) {
    if (node.owner != UINT32_MAX)
      node.owner = remap[node.owner];
    for (uint32_t &successor : node.successors)
      successor = remap[successor];
    for (uint32_t &successor : node.feedbackSuccessors)
      if (successor != UINT32_MAX)
        successor = remap[successor];
    llvm::sort(node.successors);
  }
}

bool rangesOverlap(schedule::ComputeEffectAttr lhs,
                   schedule::ComputeEffectAttr rhs) {
  if (!lhs || !rhs || lhs.getResource() != rhs.getResource() ||
      lhs.getTarget() != rhs.getTarget() ||
      lhs.getDescriptor() != rhs.getDescriptor() ||
      lhs.getFormal() != rhs.getFormal() || lhs.getWidth() == 0 ||
      rhs.getWidth() == 0)
    return false;
  // schedule::ComputeEffectAttr verification guarantees both packed ranges fit
  // in uint64_t. Keep the subtraction form so this analysis does not introduce
  // an independent overflow precondition.
  return lhs.getLow() < rhs.getLow() + rhs.getWidth() &&
         rhs.getLow() < lhs.getLow() + lhs.getWidth();
}

/// Inventory closed zero-time activations using current graph identities.
/// Always_comb and always_latch retain their source predicates and stores;
/// neither keyword proves that every output is assigned on every activation.
/// Reads through dynamic selectors and unrepresented effects remain boundaries.
/// Possible feedback edges are retained, including mux-dependent routes: graph
/// shape never proves a route inactive under the current configuration.
SmallVector<NativeRankedEvalNode>
collectRankedNodes(ModuleOp module, const ResolvedNativeEvalPlan &plan,
                   const NativeStateLayout &stateLayout,
                   const NativeStaticFanoutPlan &fanout,
                   ArrayRef<NativeDirectFragment> directFragments,
                   schedule::ComputeGraphAttr graph,
                   const NativeActivationInputs &activationInputs) {
  if (!graph)
    return {};
  const auto &sparseWires = stateLayout.isolatedSparseDriverRanges;
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos sparse scheduling nets: " << sparseWires.size()
                 << '\n';
  llvm::StringMap<sim::SimFuncOp> functions;
  module.walk([&](sim::SimFuncOp function) {
    functions.try_emplace(function.getSymName(), function);
  });
  DenseMap<uint32_t, schedule::ComputeFragmentAttr> fragments;
  for (Attribute raw : graph.getNodes())
    if (auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw))
      fragments.try_emplace(fragment.getId(), fragment);
  llvm::StringMap<const NativeDirectFragment *> directByWrapper;
  for (const auto &direct : directFragments)
    directByWrapper.try_emplace(direct.wrapper, &direct);
  struct Range {
    uint32_t state;
    uint64_t low, high;
  };
  auto normalizeRanges = [](SmallVectorImpl<Range> &ranges) {
    llvm::sort(ranges, [](const Range &a, const Range &b) {
      return std::tie(a.state, a.low, a.high) <
             std::tie(b.state, b.low, b.high);
    });
    size_t kept = 0;
    for (Range range : ranges) {
      if (kept && ranges[kept - 1].state == range.state &&
          ranges[kept - 1].high >= range.low)
        ranges[kept - 1].high = std::max(ranges[kept - 1].high, range.high);
      else
        ranges[kept++] = range;
    }
    ranges.resize(kept);
  };
  auto overlap = [](ArrayRef<Range> reads, ArrayRef<Range> writes) {
    size_t r = 0, w = 0;
    while (r < reads.size() && w < writes.size()) {
      const auto &read = reads[r];
      const auto &write = writes[w];
      if (read.state < write.state ||
          (read.state == write.state && read.high <= write.low))
        ++r;
      else if (write.state < read.state || write.high <= read.low)
        ++w;
      else
        return true;
    }
    return false;
  };
  struct Node {
    NativeRankedEvalNode plan;
    SmallVector<Range> reads, writes;
    // Effects outside the state inventory. An unknown read needs every writer
    // ordered first; only an unknown write precedes every other actor.
    bool opaqueReads = false, opaqueWrites = false;
  };
  SmallVector<Node, 0> nodes;
  using ClockKey = std::tuple<uint32_t, uint32_t, uint64_t, uint64_t>;
  SmallVector<std::optional<ClockKey>> clocks(plan.mergedFragments.size());
  DenseSet<uint32_t> multipleClocks;
  for (const auto &entry : plan.fanoutEntries) {
    if (entry.merged_bit >= clocks.size() ||
        (entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK) !=
            TALOS_RT_FANOUT_DIRECT)
      continue;
    ClockKey key{entry.static_state, entry.edge, entry.low_bit,
                 entry.bit_width};
    auto &clock = clocks[entry.merged_bit];
    if ((clock && *clock != key) ||
        (entry.edge != TALOS_RT_WAIT_EDGE_POSEDGE &&
         entry.edge != TALOS_RT_WAIT_EDGE_NEGEDGE))
      multipleClocks.insert(entry.merged_bit);
    clock = key;
  }
  SmallVector<std::pair<NativeRankedEvalNode, ClockKey>, 0> clockedNodes;
  DenseMap<uint32_t, uint64_t> widths;
  for (const auto &bound : stateLayout.bounds)
    widths.try_emplace(bound.handleID, bound.width);
  APInt subsumed(std::max<size_t>(64, plan.mergedFragments.size()), 0);
  for (const APInt &mask : plan.ownerSubsumptionMasks)
    subsumed |= mask;
  for (auto [owner, record] : llvm::enumerate(plan.mergedFragments)) {
    auto found = directByWrapper.find(plan.mergedExecutors[owner]);
    if (found == directByWrapper.end())
      continue;
    const auto &direct = *found->second;
    if (direct.instanceCoordinator || direct.fragmentIDs.empty() ||
        subsumed[record.bit] || !plan.ownerSubsumptionMasks[owner].isZero())
      continue;
    // A ranked sweep selects a member's two-state body by its promotion
    // certificate alone. An uncertified path-guarded body has no certificate:
    // only its activation-local probe proves the bits it reads known, and a
    // never-written variable still holds X (IEEE 1800-2023 6.8, Table 6-7).
    // Run such a member's four-state body in the sweep.
    StringRef twoStateBody = direct.twoStateBody;
    if (sim::SimFuncOp variant = functions.lookup(twoStateBody);
        variant &&
        ::talos::schedule::has<schedule::metadata::evalPathGuardedTwoState>(
            variant) &&
        !::talos::schedule::has<
            schedule::metadata::evalPathGuardedKnownPreserving>(variant))
      twoStateBody = {};
    Node node;
    node.plan.owner = record.bit;
    node.plan.body = direct.body;
    node.plan.twoStateBody = twoStateBody.str();
    bool clocked = llvm::any_of(direct.fragmentIDs, [&](uint32_t id) {
      auto fragment = fragments.lookup(id);
      return fragment && llvm::any_of(fragment.getEffects(), [](Attribute raw) {
               return cast<schedule::ComputeEffectAttr>(raw).getEffect() ==
                      schedule::ComputeEffectKind::NBA;
             });
    });
    if (clocked && (!clocks[record.bit] || multipleClocks.contains(record.bit)))
      continue;
    // An owner that resumes in the Inactive region must not join a sweep: it
    // runs only after every Active owner of its pass. It stays a boundary, but
    // orders no Active owner (see where its reads and writes are cleared).
    bool deferred =
        owner < plan.deferredOwners.size() && plan.deferredOwners[owner];
    clocked &= !deferred;
    DenseSet<StringAttr> summarizedActivations;
    node.plan.repeatable = !clocked && activationInputs.sourceGraph == graph;
    bool safe = !deferred && llvm::all_of(direct.fragmentIDs, [&, &record =
                                                                      record](
                                                                  uint32_t id) {
      auto fragment = fragments.find(id);
      if (fragment == fragments.end() ||
          fragment->second.getRegion() != schedule::ComputeRegionKind::Active)
        return false;
      auto function =
          functions.lookup(fragment->second.getFunction().getValue());
      if (!function)
        return false;
      node.plan.repeatable &=
          activationInputs.repeatable.contains(function.getSymNameAttr());
      auto kind = function.getEntryKind();
      if (clocked ? kind != sim::EntryKind::Always &&
                        kind != sim::EntryKind::AlwaysFF
                  : kind != sim::EntryKind::Continuous &&
                        kind != sim::EntryKind::Always &&
                        kind != sim::EntryKind::AlwaysComb &&
                        kind != sim::EntryKind::PortInput &&
                        kind != sim::EntryKind::PortOutput)
        return false;
      // A closed activation may read its own blocking temporaries after
      // defining them. Whole-function may-read effects do not distinguish
      // those internal edges from feedback through the activation boundary.
      // Reuse the finite initial/resume proof and dense must-definition facts
      // before dropping such edges or admitting bounded dynamic accesses.
      // Sensitivity remains independent: a watch stays an ordering edge, unless
      // the activation is repeatable and is woken only by its live inputs.
      auto effects = fragment->second.getEffects();
      auto inputs = activationInputs.liveIns.find(function.getSymNameAttr());
      auto outputs = activationInputs.mayWrites.find(function.getSymNameAttr());
      bool activation = !clocked && activationInputs.sourceGraph == graph &&
                        inputs != activationInputs.liveIns.end() &&
                        outputs != activationInputs.mayWrites.end();
      // A repeatable activation is woken only by its live inputs (see
      // buildNativeStaticFanoutPlan); its source sensitivity orders nothing.
      bool liveWakes = activation && activationInputs.repeatable.contains(
                                         function.getSymNameAttr());
      bool effectsSafe = llvm::all_of(effects, [&, &record =
                                                       record](Attribute raw) {
        auto effect = cast<schedule::ComputeEffectAttr>(raw);
        bool net = effect.getResource() == schedule::ComputeResourceKind::Net;
        // IEEE 1800-2023 6.6.1, 4.9.1: an isolated wire whose strong,
        // undelayed drivers partition its bits can publish in one Active
        // sweep. Each source keeps its own ready predicate and exact
        // transition publication. Connected, overlapping, weak, delayed and
        // user-defined resolution remains an execution boundary.
        auto sparse = sparseWires.find(effect.getDescriptor());
        bool sparseEffect =
            sparse != sparseWires.end() &&
            (effect.getEffect() == schedule::ComputeEffectKind::Read ||
             effect.getEffect() == schedule::ComputeEffectKind::Watch);
        if (sparse != sparseWires.end() &&
            effect.getEffect() == schedule::ComputeEffectKind::Drive &&
            effect.getWidth())
          sparseEffect = llvm::any_of(sparse->second, [&](auto range) {
            return effect.getLow() >= range.first &&
                   effect.getLow() < range.second &&
                   effect.getWidth() <= range.second - effect.getLow();
          });
        // IEEE 1800-2023 23.3.3.7, 6.6.1: port-connected nets merge into one
        // simulated net, and a bit with one strong contribution reads back
        // its driver in every member. Such a slice is a plain write of each
        // member, with the same per-member publications as an isolated wire.
        if ((effect.getEffect() == schedule::ComputeEffectKind::Read ||
             effect.getEffect() == schedule::ComputeEffectKind::Watch ||
             effect.getEffect() == schedule::ComputeEffectKind::Drive) &&
            effect.getWidth())
          if (auto connected = stateLayout.connectedExclusiveDriverRanges.find(
                  effect.getDescriptor());
              connected != stateLayout.connectedExclusiveDriverRanges.end())
            sparseEffect |= llvm::any_of(connected->second, [&](auto range) {
              return effect.getLow() >= range.first &&
                     effect.getLow() < range.second &&
                     effect.getWidth() <= range.second - effect.getLow();
            });
        // LRM 6.6/6.7 leave undriven bits at Z. Preserve read/watch ranges,
        // including holes; a drive must fit one exclusive contributor range.
        // The original ready predicates and ordered publications still apply
        // (4.6, 4.9.1, 9.2.2.2.1, 9.4.2). This scheduling fact does not extend
        // the separate complete-coverage proof used by unknown-plane elision.
        bool simpleNet = !clocked && net &&
                         (stateLayout.isolatedPartitionedDriverNets.contains(
                              effect.getDescriptor()) ||
                          sparseEffect);
        // IEEE 1800-2023 4.5-4.7, 10.4.2: consecutive Active evaluations
        // may stage their NBAs in this order, but cannot commit them early.
        // Immediate stores need the separate trigger/observer proof below.
        // Bounded indexed reads/NBAs keep their existing checked lowering
        // and exact publication at the NBA barrier. Delayed NBAs and opaque
        // effects are excluded; emission also checks for runtime boundaries.
        if (effect.getEffect() != schedule::ComputeEffectKind::Read &&
            effect.getEffect() != schedule::ComputeEffectKind::Write &&
            effect.getEffect() != schedule::ComputeEffectKind::Watch &&
            !(simpleNet &&
              effect.getEffect() == schedule::ComputeEffectKind::Drive) &&
            !(clocked &&
              effect.getEffect() == schedule::ComputeEffectKind::NBA))
          return false;
        if ((effect.getResource() != schedule::ComputeResourceKind::Storage &&
             !simpleNet) ||
            effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
            (!clocked && effect.getDynamic() &&
             (!activation ||
              effect.getEffect() == schedule::ComputeEffectKind::Watch)) ||
            effect.getDeferred() || !effect.getWidth())
          return false;
        const auto &handles = net ? stateLayout.nets : stateLayout.storage;
        auto handle = handles.find(effect.getDescriptor());
        talos_rt_stable_handle_v1 decoded{};
        if (handle == handles.end() ||
            !talos_rt_stable_handle_decode(handle->second, &decoded) ||
            decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset)
          return false;
        if (net && (!stateLayout.directHandles.contains(decoded.id) ||
                    stateLayout.guardedHandles.contains(decoded.id)))
          return false;
        auto width = widths.find(decoded.id);
        if (width == widths.end() || effect.getLow() >= width->second ||
            effect.getWidth() > width->second - effect.getLow())
          return false;
        if (clocked &&
            effect.getEffect() == schedule::ComputeEffectKind::Watch) {
          uint32_t edge =
              effect.getTrigger() == schedule::ComputeTriggerKind::Posedge
                  ? TALOS_RT_WAIT_EDGE_POSEDGE
              : effect.getTrigger() == schedule::ComputeTriggerKind::Negedge
                  ? TALOS_RT_WAIT_EDGE_NEGEDGE
                  : TALOS_RT_WAIT_EDGE_CHANGE;
          if (effect.getDynamic() ||
              ClockKey{decoded.id, edge, effect.getLow(), effect.getWidth()} !=
                  *clocks[record.bit])
            return false;
        }
        Range range{decoded.id, effect.getLow(),
                    effect.getLow() + effect.getWidth()};
        if (effect.getEffect() == schedule::ComputeEffectKind::Write ||
            effect.getEffect() == schedule::ComputeEffectKind::Drive) {
          if (fanout.runtimeTransitionStates.contains(decoded.id))
            return false;
          if (clocked) {
            auto [state, edge, low, width] = *clocks[record.bit];
            // The source-order body and its per-member ready bit
            // preserve intermediate publications. A body must not change
            // its own trigger while it is inactive (LRM 9.4.2); the effect
            // range includes every possible dynamic target, not just the
            // currently selected element.
            if (decoded.id == state && range.low < low + width &&
                low < range.high)
              return false;
          } else if (!activation)
            node.writes.push_back(range);
        } else if (!clocked &&
                   (!activation ||
                    (effect.getEffect() == schedule::ComputeEffectKind::Watch &&
                     !liveWakes))) {
          node.reads.push_back(range);
        }
        return true;
      });
      if (!effectsSafe)
        return false;
      if (activation &&
          summarizedActivations.insert(function.getSymNameAttr()).second) {
        auto appendRanges = [&](auto ranges, SmallVectorImpl<Range> &dest) {
          for (auto range : ranges) {
            constexpr uint64_t netTag =
                analysis::ActivationMemoryAnalysis::netRootTag;
            const auto &handles =
                range.root & netTag ? stateLayout.nets : stateLayout.storage;
            auto handle = handles.find(range.root & ~netTag);
            talos_rt_stable_handle_v1 decoded{};
            if (handle == handles.end() ||
                !talos_rt_stable_handle_decode(handle->second, &decoded) ||
                decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC ||
                decoded.offset)
              return false;
            auto width = widths.find(decoded.id);
            if (width == widths.end() || range.low >= width->second ||
                range.width > width->second - range.low)
              return false;
            dest.push_back({decoded.id, range.low, range.low + range.width});
          }
          return true;
        };
        return appendRanges(inputs->second, node.reads) &&
               appendRanges(outputs->second, node.writes);
      }
      return true;
    });
    // IEEE 1800-2023 9.2.2.2.1 excludes written expressions from always_comb
    // sensitivity. A read-before-write source therefore cannot be treated as
    // an algebraic feedback equation and iterated to a fixed point. Keep
    // self-dependent processes on their existing executor for now.
    if (safe) {
      normalizeRanges(node.reads);
      normalizeRanges(node.writes);
      safe = !overlap(node.reads, node.writes);
    }
    if (safe && clocked) {
      node.plan.clocked = true;
      clockedNodes.emplace_back(std::move(node.plan), *clocks[record.bit]);
    } else if (safe && !node.writes.empty())
      nodes.push_back(std::move(node));
    else if (!clocked) {
      // Scheduling only the certified helper subgraph can jump over a live
      // producer that still uses its original executor. Include such owners
      // in the dependence graph as boundaries, with their conservative full
      // effect inventory. Group emission must stop at each boundary.
      node.plan.boundary = true;
      node.reads.clear();
      node.writes.clear();
      DenseSet<StringAttr> summarizedOwners;
      for (uint32_t id : direct.fragmentIDs) {
        auto fragment = fragments.lookup(id);
        if (!fragment) {
          node.opaqueReads = node.opaqueWrites = true;
          continue;
        }
        auto owner = fragment.getFunction().getAttr();
        auto inputs = activationInputs.liveIns.find(owner);
        auto outputs = activationInputs.mayWrites.find(owner);
        bool activation = activationInputs.sourceGraph == graph &&
                          inputs != activationInputs.liveIns.end() &&
                          outputs != activationInputs.mayWrites.end();
        if (activation && summarizedOwners.insert(owner).second) {
          auto appendRanges = [&](auto ranges, SmallVectorImpl<Range> &dest,
                                  bool &opaque) {
            for (auto range : ranges) {
              constexpr uint64_t netTag =
                  analysis::ActivationMemoryAnalysis::netRootTag;
              const auto &handles =
                  range.root & netTag ? stateLayout.nets : stateLayout.storage;
              auto handle = handles.find(range.root & ~netTag);
              talos_rt_stable_handle_v1 decoded{};
              if (handle == handles.end() ||
                  !talos_rt_stable_handle_decode(handle->second, &decoded) ||
                  decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC ||
                  decoded.offset) {
                opaque = true;
                continue;
              }
              auto width = widths.find(decoded.id);
              if (width == widths.end() || range.low >= width->second ||
                  range.width > width->second - range.low) {
                opaque = true;
                continue;
              }
              dest.push_back({decoded.id, range.low, range.low + range.width});
            }
          };
          appendRanges(inputs->second, node.reads, node.opaqueReads);
          appendRanges(outputs->second, node.writes, node.opaqueWrites);
        }
        for (auto effect :
             fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
          auto kind = effect.getEffect();
          if (kind != schedule::ComputeEffectKind::Read &&
              kind != schedule::ComputeEffectKind::Write &&
              kind != schedule::ComputeEffectKind::Drive &&
              kind != schedule::ComputeEffectKind::Watch)
            continue;
          // A certified activation accounts for every canonical access and
          // excludes its private scratch storage. Keep that precision even
          // when net publication or another emission restriction requires an
          // executor boundary. Unknown local effects must not invent edges to
          // every other actor. Sensitivity remains an independent constraint,
          // unless the activation is repeatable and is woken only by its live
          // inputs, which its summary already reads.
          if (activation && kind != schedule::ComputeEffectKind::Watch)
            continue;
          if (activation && activationInputs.repeatable.contains(owner))
            continue;
          bool &opaque = kind == schedule::ComputeEffectKind::Write ||
                                 kind == schedule::ComputeEffectKind::Drive
                             ? node.opaqueWrites
                             : node.opaqueReads;
          auto resource = effect.getResource();
          if ((resource != schedule::ComputeResourceKind::Storage &&
               resource != schedule::ComputeResourceKind::Net) ||
              effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
              !effect.getWidth()) {
            opaque = true;
            continue;
          }
          // The whole-program effect solver already maps driver publications
          // to their net and expands collapsed port aliases. A known net is
          // a distinct address space, not an unknown write to all storage.
          // Keep its executor as a boundary: ordering does not bypass net
          // resolution, strengths, delay handling, or transition observers.
          const auto &handles = resource == schedule::ComputeResourceKind::Net
                                    ? stateLayout.nets
                                    : stateLayout.storage;
          auto handle = handles.find(effect.getDescriptor());
          talos_rt_stable_handle_v1 decoded{};
          if (handle == handles.end() ||
              !talos_rt_stable_handle_decode(handle->second, &decoded) ||
              decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC ||
              decoded.offset) {
            opaque = true;
            continue;
          }
          auto width = widths.find(decoded.id);
          if (width == widths.end() || effect.getLow() >= width->second ||
              effect.getWidth() > width->second - effect.getLow()) {
            opaque = true;
            continue;
          }
          Range range{decoded.id, effect.getLow(),
                      effect.getLow() + effect.getWidth()};
          (kind == schedule::ComputeEffectKind::Write ||
                   kind == schedule::ComputeEffectKind::Drive
               ? node.writes
               : node.reads)
              .push_back(range);
        }
      }
      // IEEE 1800-2023 4.4.2.3: an owner resuming in the Inactive region runs
      // only when no Active owner is pending, and takes the highest bits below.
      // It cannot interleave with an Active sweep, so its reads and writes
      // order nothing there; its publications start the next pass.
      if (deferred) {
        node.reads.clear();
        node.writes.clear();
        node.opaqueReads = node.opaqueWrites = false;
      }
      normalizeRanges(node.reads);
      normalizeRanges(node.writes);
      nodes.push_back(std::move(node));
    }
  }
  struct Reader {
    uint64_t low, high, prefixHigh;
    uint32_t owner;
  };
  if (native::has<native::DebugTiming>(module))
    for (const auto &node : nodes)
      llvm::errs() << "talos ranked memory: body=" << node.plan.body
                   << " reads=" << node.reads.size()
                   << " writes=" << node.writes.size() << '\n';
  DenseMap<uint32_t, SmallVector<Reader>> readers;
  for (const auto &node : nodes)
    for (const auto &read : node.reads)
      readers[read.state].push_back({read.low, read.high, 0, node.plan.owner});
  for (auto &[state, ranges] : readers) {
    llvm::sort(ranges, [](const Reader &a, const Reader &b) {
      return std::tie(a.low, a.high, a.owner) <
             std::tie(b.low, b.high, b.owner);
    });
    uint64_t high = 0;
    for (auto &range : ranges)
      range.prefixHigh = high = std::max(high, range.high);
  }
  SmallVector<uint32_t> opaqueReaders;
  for (const auto &node : nodes)
    if (node.opaqueReads)
      opaqueReaders.push_back(node.plan.owner);
  SmallVector<NativeRankedEvalNode> result;
  DenseSet<StringAttr> internalSources;
  for (auto &node : nodes) {
    if (!node.plan.boundary) {
      const auto *direct =
          directByWrapper.lookup(plan.mergedExecutors[node.plan.owner]);
      for (uint32_t id : direct->fragmentIDs)
        internalSources.insert(fragments.lookup(id).getFunction().getAttr());
    }
    if (node.opaqueWrites) {
      for (const auto &other : nodes)
        if (node.plan.owner != other.plan.owner)
          node.plan.successors.push_back(other.plan.owner);
    } else if (!node.writes.empty()) {
      for (uint32_t reader : opaqueReaders)
        if (node.plan.owner != reader)
          node.plan.successors.push_back(reader);
    }
    for (const auto &write : node.writes) {
      auto &ranges = readers[write.state];
      auto next = llvm::lower_bound(
          ranges, write.high,
          [](const Reader &r, uint64_t high) { return r.low < high; });
      while (next != ranges.begin()) {
        const auto &read = *--next;
        if (read.prefixHigh <= write.low)
          break;
        if (read.high > write.low)
          node.plan.successors.push_back(read.owner);
      }
    }
    llvm::sort(node.plan.successors);
    node.plan.successors.erase(
        std::unique(node.plan.successors.begin(), node.plan.successors.end()),
        node.plan.successors.end());
    result.push_back(std::move(node.plan));
  }
  DenseMap<uint32_t, uint32_t> dense;
  for (auto [id, node] : llvm::enumerate(result))
    dense.try_emplace(node.owner, id);
  std::vector<std::pair<uint32_t, uint32_t>> edges;
  for (auto [id, node] : llvm::enumerate(result))
    for (uint32_t target : node.successors)
      edges.emplace_back(id, dense.lookup(target));
  const unsigned realNodeCount = result.size();
  // Runtime-owned actors have no bit in the generated ready set. They must
  // nevertheless constrain SCCs and segment boundaries: A -> runtime B -> C
  // is not a closed A/C graph. These virtual nodes are analysis-only and never
  // enter an ABI table, an owner permutation, or executable group membership.
  DenseMap<uint32_t, SmallVector<uint32_t>> byFragment;
  DenseMap<StringAttr, SmallVector<uint32_t>> byFunction;
  for (auto [id, node] : llvm::enumerate(result)) {
    const auto *direct =
        directByWrapper.lookup(plan.mergedExecutors[node.owner]);
    for (uint32_t fragmentID : direct->fragmentIDs) {
      byFragment[fragmentID].push_back(id);
      byFunction[fragments.lookup(fragmentID).getFunction().getAttr()]
          .push_back(id);
    }
  }
  for (auto &[name, owners] : byFunction) {
    llvm::sort(owners);
    owners.erase(std::unique(owners.begin(), owners.end()), owners.end());
  }
  DenseMap<StringAttr, unsigned> eventWaits;
  DenseSet<StringAttr> otherBoundaries;
  DenseMap<StringAttr, uint32_t> entries;
  DenseMap<uint32_t, SmallVector<uint32_t>> sourceOrder;
  for (Attribute raw : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment)
      continue;
    auto name = fragment.getFunction().getAttr();
    if (fragment.getBlock() == 0)
      entries[name] = fragment.getId();
    switch (fragment.getAction()) {
    case schedule::ComputeActionKind::Continue:
    case schedule::ComputeActionKind::Terminate:
      break;
    case schedule::ComputeActionKind::SuspendChange:
    case schedule::ComputeActionKind::SuspendAny:
    case schedule::ComputeActionKind::SuspendEdge:
      ++eventWaits[name];
      break;
    default:
      otherBoundaries.insert(name);
      break;
    }
  }
  for (Attribute raw : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(raw);
    if (edge.getKind() == schedule::ComputeEdgeKind::ProcessOrder)
      sourceOrder[edge.getSource()].push_back(edge.getTarget());
  }
  DenseMap<StringAttr, bool> repeatingActivations;
  DenseMap<StringAttr, uint32_t> virtualActivations;
  for (Attribute raw : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment || fragment.getRegion() != schedule::ComputeRegionKind::Active)
      continue;
    auto function = functions.lookup(fragment.getFunction().getValue());
    if (!function || function.getEntryKind() == sim::EntryKind::RootInitializer)
      continue;
    StringAttr name = function.getSymNameAttr();
    auto [shape, inserted] = repeatingActivations.try_emplace(name, false);
    if (inserted) {
      auto kind = function.getEntryKind();
      bool settling = analysis::isSettlingEntryKind(kind);
      bool repeating = kind == sim::EntryKind::Always ||
                       kind == sim::EntryKind::AlwaysFF;
      shape->second = (settling || repeating) && eventWaits.lookup(name) == 1 &&
                      !otherBoundaries.contains(name);
      if (shape->second && !settling) {
        // An arbitrary initial/task is never a repeating activation. Even an
        // always procedure may publish a distinct prefix before its first
        // event wait. Collapse only a setup prefix with no design effects;
        // resumed bodies then share the authoritative existing ready owner.
        SmallVector<uint32_t> pending;
        DenseSet<uint32_t> seen;
        if (auto entry = entries.find(name); entry != entries.end())
          pending.push_back(entry->second);
        else
          shape->second = false;
        while (shape->second && !pending.empty()) {
          uint32_t id = pending.pop_back_val();
          if (!seen.insert(id).second)
            continue;
          auto prefix = fragments.lookup(id);
          if (!prefix || prefix.getFunction().getAttr() != name) {
            shape->second = false;
            break;
          }
          auto action = prefix.getAction();
          if (action == schedule::ComputeActionKind::SuspendChange ||
              action == schedule::ComputeActionKind::SuspendAny ||
              action == schedule::ComputeActionKind::SuspendEdge)
            continue;
          if (!prefix.getEffects().empty()) {
            shape->second = false;
            break;
          }
          llvm::append_range(pending, sourceOrder.lookup(id));
        }
      }
    }
    bool single = shape->second;
    if (single && byFunction.lookup(name).size() == 1) {
      byFragment[fragment.getId()] = byFunction.lookup(name);
      continue;
    }
    if (byFragment.contains(fragment.getId()))
      continue;
    auto found = virtualActivations.find(name);
    uint32_t id = found != virtualActivations.end() && single
                      ? found->second
                      : result.size();
    if (id == result.size()) {
      NativeRankedEvalNode boundary;
      boundary.owner = UINT32_MAX;
      boundary.body = (Twine("<runtime:") + function.getSymName() + ":" +
                       Twine(fragment.getBlock()) + ">")
                          .str();
      boundary.boundary = true;
      result.push_back(std::move(boundary));
      if (single)
        virtualActivations[name] = id;
    }
    byFragment[fragment.getId()] = {id};
  }
  DenseMap<uint32_t, SmallVector<uint32_t>> resumes;
  for (Attribute raw : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(raw);
    if (edge.getKind() == schedule::ComputeEdgeKind::Resume)
      resumes[edge.getSource()].push_back(edge.getTarget());
  }
  auto project = [&](uint32_t source, uint32_t target, bool sensitivity) {
    for (uint32_t from : byFragment.lookup(source))
      for (uint32_t to : byFragment.lookup(target))
        // Existing real owners already have refined read/watch dependencies.
        // A coarse source summary must not erase that precision. Add missing
        // boundary paths, retaining the original fanout for every watch.
        if (from != to &&
            (!sensitivity || from >= realNodeCount || to >= realNodeCount))
          edges.emplace_back(from, to);
  };
  for (Attribute raw : graph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(raw);
    if (edge.getKind() != schedule::ComputeEdgeKind::ProcessOrder &&
        edge.getKind() != schedule::ComputeEdgeKind::Sensitivity)
      continue;
    bool sensitivity = edge.getKind() == schedule::ComputeEdgeKind::Sensitivity;
    project(edge.getSource(), edge.getTarget(), sensitivity);
    if (edge.getKind() == schedule::ComputeEdgeKind::Sensitivity)
      for (uint32_t target : resumes[edge.getTarget()])
        project(edge.getSource(), target, true);
  }
  // Keep independent cones in separate helper bodies. Interleaving their
  // equally legal topological ranks would sweep unrelated predicates whenever
  // only one cone receives an activation.
  SmallVector<uint32_t> islands(result.size());
  std::iota(islands.begin(), islands.end(), 0);
  auto root = [&](uint32_t node) {
    while (islands[node] != node) {
      islands[node] = islands[islands[node]];
      node = islands[node];
    }
    return node;
  };
  for (auto [from, to] : edges) {
    uint32_t a = root(from), b = root(to);
    islands[std::max(a, b)] = std::min(a, b);
  }
  for (uint32_t id = 0; id < result.size(); ++id)
    result[id].island = root(id) < realNodeCount
                            ? root(id)
                            : realNodeCount + clockedNodes.size() + root(id);
  runtime::ActivationOrder order;
  if (!runtime::ActivationOrder::build(result.size(), edges, order))
    return {};
  // Events from executors outside the pure graph are independent activity
  // seeds. Do not seed internal lane publications: that would split a closed
  // forward chain at every wire. Startup remains the original pending work.
  DenseMap<uint32_t, SmallVector<Range>> externalWrites;
  bool unknownExternal = false;
  for (Attribute raw : graph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment || internalSources.contains(fragment.getFunction().getAttr()))
      continue;
    auto function = functions.lookup(fragment.getFunction().getValue());
    if (function && function.getEntryKind() == sim::EntryKind::RootInitializer)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::Write &&
          effect.getEffect() != schedule::ComputeEffectKind::Drive &&
          effect.getEffect() != schedule::ComputeEffectKind::NBA)
        continue;
      bool net = effect.getResource() == schedule::ComputeResourceKind::Net;
      if ((!net &&
           effect.getResource() != schedule::ComputeResourceKind::Storage) ||
          effect.getTarget() != schedule::ComputeTargetKind::Descriptor ||
          !effect.getWidth() ||
          effect.getLow() > UINT64_MAX - effect.getWidth()) {
        unknownExternal = true;
        continue;
      }
      const auto &handles = net ? stateLayout.nets : stateLayout.storage;
      auto handle = handles.find(effect.getDescriptor());
      talos_rt_stable_handle_v1 decoded{};
      if (handle == handles.end() ||
          !talos_rt_stable_handle_decode(handle->second, &decoded) ||
          decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset) {
        unknownExternal = true;
        continue;
      }
      externalWrites[decoded.id].push_back(
          {decoded.id, effect.getLow(), effect.getLow() + effect.getWidth()});
    }
  }
  const unsigned componentCount = order.componentOffsets.size() - 1;
  SmallVector<llvm::SparseBitVector<>> activities(result.size());
  std::map<ClockKey, unsigned> events;
  for (const auto &entry : plan.fanoutEntries) {
    if ((entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK) != TALOS_RT_FANOUT_DIRECT)
      continue;
    auto node = dense.find(entry.merged_bit);
    if (node == dense.end())
      continue;
    bool external = unknownExternal ||
                    fanout.runtimeTransitionStates.contains(entry.static_state);
    if (auto found = externalWrites.find(entry.static_state);
        found != externalWrites.end())
      external |= llvm::any_of(found->second, [&](const Range &write) {
        return !entry.bit_width ||
               (write.low < entry.low_bit + entry.bit_width &&
                entry.low_bit < write.high);
      });
    if (!external)
      continue;
    auto [event, inserted] =
        events.try_emplace(ClockKey{entry.static_state, entry.edge,
                                    entry.low_bit, entry.bit_width},
                           events.size());
    activities[node->second].set(event->second);
  }
  // A residual feedback event starts a new affected-component sweep. Its
  // domain flows only forward through the condensation DAG; unrelated cones
  // sharing an external clock do not join the retry. Identities are rebuilt
  // here after all source graph rewriting, before native IR is emitted.
  const unsigned externalEvents = events.size();
  unsigned nextEvent = externalEvents;
  for (auto [from, to] : order.feedback)
    activities[to].set(nextEvent++);
  SmallVector<unsigned> position(result.size());
  for (auto [rank, node] : llvm::enumerate(order.nodes))
    position[node] = rank;
  SmallVector<SmallVector<unsigned>> forward(result.size());
  for (auto [from, to] : edges)
    if (position[from] < position[to])
      forward[from].push_back(to);
  // Propagate through forward edges INSIDE an SCC as well. Unioning all of
  // an SCC's seeds first would replay unrelated portions of a large component
  // on every backward event. Each backedge instead seeds its own destination.
  for (unsigned node : order.nodes)
    for (unsigned target : forward[node])
      activities[target] |= activities[node];
  std::map<std::vector<unsigned>, unsigned> domains;
  for (unsigned id = 0; id < result.size(); ++id) {
    std::vector<unsigned> key;
    for (unsigned event : activities[id])
      key.push_back(event);
    result[id].activityDomain =
        domains.try_emplace(std::move(key), domains.size()).first->second;
  }
  for (unsigned id = 0; id < result.size(); ++id) {
    auto &node = result[id];
    node.component = order.componentOf[id];
    node.cyclic = order.cyclic[node.component];
  }
  for (auto [from, to] : edges)
    if (order.componentOf[from] != order.componentOf[to])
      result[from].successorComponents.push_back(order.componentOf[to]);
  for (auto &node : result) {
    llvm::sort(node.successorComponents);
    node.successorComponents.erase(std::unique(node.successorComponents.begin(),
                                               node.successorComponents.end()),
                                   node.successorComponents.end());
  }
  for (auto [from, to] : order.feedback)
    result[from].feedbackSuccessors.push_back(result[to].owner);
  // Independent runtime sources need not interrupt a closed forward sweep.
  // Move components with no native ancestor before it, and terminal runtime
  // observers after it. A boundary on A -> B -> C has both a native ancestor
  // and descendant, so remains between the computations. This is only a
  // topological tie-break; actual runtime execution stays at its handoff.
  SmallVector<bool> nativeBefore(componentCount), nativeAfter(componentCount);
  for (unsigned id = 0; id < realNodeCount; ++id) {
    nativeBefore[order.componentOf[id]] = true;
    nativeAfter[order.componentOf[id]] = true;
  }
  for (unsigned component = 0; component < componentCount; ++component)
    for (unsigned i = order.successorOffsets[component];
         i < order.successorOffsets[component + 1]; ++i)
      nativeBefore[order.successors[i]] =
          nativeBefore[order.successors[i]] || nativeBefore[component];
  for (unsigned component = componentCount; component-- > 0;)
    for (unsigned i = order.successorOffsets[component];
         i < order.successorOffsets[component + 1]; ++i)
      nativeAfter[component] =
          nativeAfter[component] || nativeAfter[order.successors[i]];
  auto boundaryPhase = [&](unsigned node) {
    unsigned component = order.componentOf[node];
    return !nativeBefore[component] ? 0 : !nativeAfter[component] ? 2 : 1;
  };
  llvm::stable_sort(order.nodes, [&](uint32_t a, uint32_t b) {
    if (result[a].island != result[b].island)
      return result[a].island < result[b].island;
    return boundaryPhase(a) < boundaryPhase(b);
  });
  SmallVector<NativeRankedEvalNode> ranked;
  for (uint32_t id : order.nodes)
    ranked.push_back(std::move(result[id]));
  // Each exact physical edge gets a fixed-order direct-call sequence, using
  // the existing ready/proof/NBA-taint protocol. Independent clocks and async
  // resets stay separate. A checkpoint can enqueue a subset, so emission still
  // checks every member's ready bit instead of inventing co-activations.
  DenseMap<ClockKey, uint32_t> cohorts;
  uint32_t nextIsland = realNodeCount;
  for (auto &[node, clock] : clockedNodes) {
    auto [cohort, inserted] = cohorts.try_emplace(clock, nextIsland);
    nextIsland += inserted;
    node.island = cohort->second;
    node.component = componentCount + cohort->second;
    node.activityDomain = domains.size() + cohort->second;
    ranked.push_back(std::move(node));
  }
  return ranked;
}

} // namespace

NativeActivationInputs collectNativeActivationInputs(sim::SimDesignOp design,
                                                     bool explain) {
  NativeActivationInputs result;
  if (!design || !(result.sourceGraph = design.getComputeGraphAttr()))
    return result;
  analysis::HandleDataflowAnalysis handles(design);
  result.repeatable =
      schedule::collectRepeatableCombinationalActivations(design, handles);
  if (explain)
    llvm::errs() << "talos repeatable activations: "
                 << result.repeatable.size() << '\n';
  result.completeNBAWriters = true;
  SymbolTable symbols(design);
  llvm::MapVector<StringAttr, SmallVector<schedule::ComputeEffectAttr>>
      effectsByOwner;
  DenseSet<StringAttr> changeOwners;
  for (auto raw : result.sourceGraph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(raw);
    if (!fragment)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getEffect() != schedule::ComputeEffectKind::NBA)
        continue;
      if (effect.getResource() != schedule::ComputeResourceKind::Storage ||
          effect.getTarget() != schedule::ComputeTargetKind::Descriptor) {
        result.completeNBAWriters = false;
        continue;
      }
      result.nbaWriters[effect.getDescriptor()].push_back(fragment.getId());
    }
    StringAttr owner = fragment.getFunction().getAttr();
    if (fragment.getAction() == schedule::ComputeActionKind::SuspendChange ||
        fragment.getAction() == schedule::ComputeActionKind::SuspendAny)
      changeOwners.insert(owner);
    llvm::append_range(
        effectsByOwner[owner],
        fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>());
  }
  const uint64_t laneBudget =
      schedule::getMaxInlineOperations(design->getParentOfType<ModuleOp>());
  struct Request {
    sim::SimFuncOp function;
    bool lanes;
  };
  SmallVector<Request, 0> requests;
  for (const auto &[owner, effects] : effectsByOwner) {
    if (!changeOwners.contains(owner))
      continue;
    auto function = symbols.lookup<sim::SimFuncOp>(owner.getValue());
    if (!function)
      continue;
    uint64_t cost = 0;
    bool needsLanes = result.repeatable.contains(owner) &&
                      !function
                           .walk([&](Operation *) {
                             return ++cost > laneBudget
                                        ? WalkResult::interrupt()
                                        : WalkResult::advance();
                           })
                           .wasInterrupted();
    bool needsProof =
        needsLanes ||
        llvm::any_of(effects, [&, &effects = effects](auto effect) {
          if (effect.getDynamic())
            return true;
          if (effect.getEffect() != schedule::ComputeEffectKind::Read)
            return false;
          return llvm::any_of(effects, [&](auto write) {
            return write.getEffect() == schedule::ComputeEffectKind::Write &&
                   rangesOverlap(effect, write);
          });
        });
    if (needsProof)
      requests.push_back({function, needsLanes});
  }
  struct Facts {
    analysis::ActivationMemoryAnalysis::Ranges liveIns, mayWrites;
    bool usable = false;
    std::string trace;
  };
  SmallVector<Facts, 0> facts(requests.size());
  auto solve = [&](size_t index) {
    sim::SimFuncOp function = requests[index].function;
    analysis::ActivationRegionAnalysis activation(
        function, handles, {},
        requests[index].lanes
            ? analysis::ActivationMemoryAnalysis::DependencyMode::ReachingValues
            : analysis::ActivationMemoryAnalysis::DependencyMode::Inputs);
    const auto &memory = activation.getMemory();
    Facts &fact = facts[index];
    if (explain) {
      llvm::raw_string_ostream os(fact.trace);
      os << "talos ranked activation: " << function.getSymName()
         << " valid=" << activation.isValid()
         << " complete=" << memory.hasCompleteWrites()
         << " inputs=" << memory.hasInputDependencies()
         << " input_reason=" << memory.getDependencyFailure() << " reason="
         << analysis::stringifyActivationFailure(activation.getFailureReason())
         << '\n';
    }
    if (activation.isValid() && memory.hasCompleteWrites()) {
      fact.usable = true;
      llvm::append_range(fact.liveIns, memory.hasInputDependencies()
                                           ? memory.getValueInputs()
                                           : memory.getLiveIns());
      llvm::append_range(fact.mayWrites, memory.getMayWrites());
    }
  };
  // A worker solves only a private clone of its own function. Call summaries
  // read shared callees, whose solves fold in place, so those owners stay on
  // this thread.
  SmallVector<size_t, 0> callFree, withCalls;
  for (auto [index, request] : llvm::enumerate(requests))
    (request.function
             .walk([](sim::SimCallOp) { return WalkResult::interrupt(); })
             .wasInterrupted()
         ? withCalls
         : callFree)
        .push_back(index);
  analysis::parallelForChunked(design.getContext(), callFree.size(),
                               [&](size_t index) { solve(callFree[index]); });
  for (size_t index : withCalls)
    solve(index);
  for (auto [request, fact] : llvm::zip_equal(requests, facts)) {
    llvm::errs() << fact.trace;
    if (!fact.usable)
      continue;
    StringAttr name = request.function.getSymNameAttr();
    result.liveIns[name] = std::move(fact.liveIns);
    result.mayWrites[name] = std::move(fact.mayWrites);
  }
  return result;
}

FailureOr<ResolvedNativeEvalPlan>
resolveNativeEvalPlan(ModuleOp module,
                      ArrayRef<talos_rt_native_schedule_node> executableNodes,
                      const NativeStateLayout &stateLayout,
                      const NativeStaticNBAPlan &staticNBAPlan,
                      const NativeStaticFanoutPlan &staticFanoutPlan,
                      ArrayRef<NativeDirectFragment> directFragments,
                      const NativeEvalOwnershipPlan &evalOwnership,
                      schedule::ComputeGraphAttr computeGraph,
                      const NativeActivationInputs &activationInputs,
                      ArrayRef<NativePeriodicClock> periodicClocks,
                      ArrayRef<NativePeriodicAlias> periodicAliases) {
  ResolvedNativeEvalPlan result;
  if (!staticFanoutPlan.exact)
    return result;
  result.fanoutEntries.assign(staticFanoutPlan.entries.begin(),
                              staticFanoutPlan.entries.end());
  auto setFanoutRoute = [](talos_rt_static_fanout_entry &entry,
                           uint32_t route) {
    entry.reserved = (entry.reserved & ~TALOS_RT_FANOUT_ROUTE_MASK) | route;
  };
  // The first executable node of each physical continuation.
  DenseMap<std::pair<uint32_t, uint32_t>, uint32_t> nodeByContinuation;
  for (auto [index, node] : llvm::enumerate(executableNodes))
    nodeByContinuation.try_emplace({node.actor_slot, node.continuation},
                                   static_cast<uint32_t>(index));
  for (talos_rt_static_fanout_entry &entry : result.fanoutEntries) {
    auto node = nodeByContinuation.find({entry.actor_slot, entry.continuation});
    if (node == nodeByContinuation.end())
      return module.emitError("static fanout has no indexed compute fragment"),
             failure();
    entry.compute_node = node->second;
    setFanoutRoute(entry, TALOS_RT_FANOUT_RUNTIME);
    result.clockKernels.push_back(
        {entry.static_state, entry.edge, entry.low_bit, entry.bit_width});
  }
  llvm::sort(result.clockKernels, [](const auto &lhs, const auto &rhs) {
    return lhs.key() < rhs.key();
  });
  result.clockKernels.erase(std::unique(result.clockKernels.begin(),
                                        result.clockKernels.end(),
                                        [](const auto &lhs, const auto &rhs) {
                                          return lhs.key() == rhs.key();
                                        }),
                            result.clockKernels.end());
  for (auto [index, kernel] : llvm::enumerate(result.clockKernels))
    kernel.activeName =
        (Twine("__talos_aot_model_active_v1_") + Twine(index)).str();

  if (evalOwnership.fanoutOwners.size() != result.fanoutEntries.size() ||
      evalOwnership.periodicFanoutOwners.size() != result.fanoutEntries.size())
    return module.emitError("eval ownership plan does not match fanout"),
           failure();
  result.periodicOwnerBits.assign(result.fanoutEntries.size(), UINT32_MAX);
  // Each executor's merged records, in record order.
  llvm::StringMap<SmallVector<uint32_t, 1>> mergedByExecutor;
  auto resolveOwner =
      [&](const NativeEvalFanoutOwner &plannedOwner,
          const talos_rt_static_fanout_entry &entry) -> FailureOr<uint32_t> {
    if (plannedOwner.kind != NativeEvalFanoutOwnerKind::Direct ||
        plannedOwner.directFragment >= directFragments.size())
      return module.emitError(
                 "generated eval owner references an invalid direct fragment"),
             failure();
    const NativeDirectFragment &direct =
        directFragments[plannedOwner.directFragment];
    SmallVector<uint32_t, 1> &records = mergedByExecutor[direct.wrapper];
    auto merged = llvm::find_if(records, [&](uint32_t index) {
      return result.mergedFragments[index].actor_slot == direct.actorSlot &&
             result.mergedFragments[index].continuation == direct.continuation;
    });
    if (merged != records.end()) {
      auto &record = result.mergedFragments[*merged];
      record.compute_node = std::min(record.compute_node, entry.compute_node);
      return record.bit;
    }
    uint32_t bit = static_cast<uint32_t>(result.mergedFragments.size());
    records.push_back(bit);
    result.mergedFragments.push_back({direct.actorSlot, direct.continuation,
                                      entry.kernel, bit, entry.compute_node, 0,
                                      nullptr});
    result.deferredOwners.push_back(direct.deferred);
    result.mergedExecutors.push_back(direct.wrapper);
    result.mergedTwoStateExecutors.push_back(direct.twoStateWrapper);
    result.mergedPromotionRanges.emplace_back();
    llvm::append_range(result.mergedPromotionRanges.back(),
                       direct.promotionRanges);
    return bit;
  };
  for (auto [entryIndex, entry] : llvm::enumerate(result.fanoutEntries)) {
    auto trigger = llvm::lower_bound(
        result.clockKernels,
        std::tuple{entry.static_state, entry.low_bit, entry.bit_width,
                   static_cast<uint32_t>(entry.edge)},
        [](const NativeEvalClockKernel &kernel, const auto &key) {
          return kernel.key() < key;
        });
    if (trigger == result.clockKernels.end() ||
        trigger->key() != std::tuple{entry.static_state, entry.low_bit,
                                     entry.bit_width,
                                     static_cast<uint32_t>(entry.edge)})
      return module.emitError("could not index generated eval trigger"),
             failure();
    entry.kernel = static_cast<uint32_t>(trigger - result.clockKernels.begin());

    const NativeEvalFanoutOwner &plannedOwner =
        evalOwnership.fanoutOwners[entryIndex];
    if (plannedOwner.kind == NativeEvalFanoutOwnerKind::PeriodicAlias) {
      setFanoutRoute(entry, TALOS_RT_FANOUT_PERIODIC_ALIAS);
      entry.merged_bit = 0;
      continue;
    }
    // Runtime-owned entries describe transient Tier-3 work (for example a
    // finite reset sequencer) that must be drained before the periodic
    // handoff.  They retain their compute-node identity in the fanout table,
    // but are not members of the closed Tier-1/Tier-2 ready set.  Admitting a
    // null executor here would make the hot coordinator's ownership model
    // incomplete after handoff.
    if (plannedOwner.kind == NativeEvalFanoutOwnerKind::Runtime) {
      setFanoutRoute(entry, TALOS_RT_FANOUT_RUNTIME);
      entry.merged_bit = 0;
      continue;
    }
    FailureOr<uint32_t> genericBit = resolveOwner(plannedOwner, entry);
    if (failed(genericBit))
      return failure();
    entry.merged_bit = *genericBit;
    setFanoutRoute(entry, TALOS_RT_FANOUT_DIRECT);

    const NativeEvalFanoutOwner &periodicOwner =
        evalOwnership.periodicFanoutOwners[entryIndex];
    if (periodicOwner.kind != NativeEvalFanoutOwnerKind::Direct)
      continue;
    FailureOr<uint32_t> periodicBit = resolveOwner(periodicOwner, entry);
    if (failed(periodicBit))
      return failure();
    if (*periodicBit != *genericBit)
      result.periodicOwnerBits[entryIndex] = *periodicBit;
  }

  if (!result.mergedFragments.empty()) {
    SmallVector<uint32_t> order(result.mergedFragments.size());
    std::iota(order.begin(), order.end(), 0u);
    llvm::sort(order, [&](unsigned lhs, unsigned rhs) {
      const auto &left = result.mergedFragments[lhs];
      const auto &right = result.mergedFragments[rhs];
      return std::tuple{left.compute_node, left.actor_slot, left.continuation} <
             std::tuple{right.compute_node, right.actor_slot,
                        right.continuation};
    });
    reorderOwners(result, order);
  }

  // Promotion belongs to the exact periodic execution closure. Follow graph
  // activation and matching NBA stage/activate ranges without pulling dormant
  // asynchronous owners into the scan.
  if (!result.mergedFragments.empty() && computeGraph) {
    llvm::SmallDenseSet<unsigned, 32> closure;
    auto periodicBitTouches = [](uint64_t bit,
                                 const talos_rt_static_fanout_entry &entry) {
      if (entry.bit_width == 0 || entry.low_bit > bit ||
          bit - entry.low_bit >= entry.bit_width)
        return false;
      // IEEE 1800 edge events on a vector observe only the expression's least
      // significant bit. Ordinary change events observe the complete range.
      return entry.edge == TALOS_RT_WAIT_EDGE_CHANGE || entry.low_bit == bit;
    };
    // The state-local bit of a periodic source, if it lies in its state.
    auto localBit = [&](uint64_t state,
                        uint64_t offset) -> std::optional<uint64_t> {
      const auto *bound = stateLayout.findBound(state);
      if (!bound || offset < bound->offset ||
          offset - bound->offset >= bound->width)
        return std::nullopt;
      return offset - bound->offset;
    };
    SmallVector<std::optional<uint64_t>> clockBits, aliasBits;
    for (const NativePeriodicClock &clock : periodicClocks)
      clockBits.push_back(
          localBit(clock.getStaticState(), clock.getBitOffset()));
    for (const NativePeriodicAlias &alias : periodicAliases)
      aliasBits.push_back(
          localBit(alias.getTargetStaticState(), alias.getTargetBitOffset()));
    auto clockTouches = [&](size_t index,
                            const talos_rt_static_fanout_entry &entry) {
      if (entry.static_state != periodicClocks[index].getStaticState() ||
          entry.bit_width == 0 || !clockBits[index])
        return false;
      return periodicBitTouches(*clockBits[index], entry);
    };
    auto aliasTouches = [&](size_t index,
                            const talos_rt_static_fanout_entry &entry) {
      if (entry.static_state != periodicAliases[index].getTargetStaticState() ||
          entry.bit_width == 0 || !aliasBits[index])
        return false;
      return periodicBitTouches(*aliasBits[index], entry);
    };
    for (auto [entryIndex, entry] : llvm::enumerate(result.fanoutEntries)) {
      uint32_t route = entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK;
      if (route == TALOS_RT_FANOUT_RUNTIME ||
          route == TALOS_RT_FANOUT_PERIODIC_ALIAS ||
          entry.merged_bit >= result.mergedFragments.size())
        continue;
      bool periodic = false;
      for (size_t index = 0; index != periodicClocks.size() && !periodic;
           ++index)
        periodic = clockTouches(index, entry);
      for (size_t index = 0; index != periodicAliases.size() && !periodic;
           ++index)
        periodic = aliasTouches(index, entry);
      if (periodic) {
        uint32_t owner = result.periodicOwnerBits[entryIndex] == UINT32_MAX
                             ? entry.merged_bit
                             : result.periodicOwnerBits[entryIndex];
        if (owner < result.mergedFragments.size())
          closure.insert(owner);
      }
    }
    const llvm::SmallDenseSet<unsigned, 32> periodicSeeds = closure;
    result.periodicEntryRecords.assign(periodicSeeds.begin(),
                                       periodicSeeds.end());
    llvm::sort(result.periodicEntryRecords);

    SmallVector<SmallVector<uint32_t>> ownerFragments(
        result.mergedFragments.size());
    SmallVector<bool> ownerIsCoordinator(result.mergedFragments.size(), false);
    SmallVector<uint32_t> ownerFusionGroups(result.mergedFragments.size(),
                                            UINT32_MAX);
    llvm::StringMap<SmallVector<unsigned, 1>> directsByWrapper;
    for (auto [index, direct] : llvm::enumerate(directFragments))
      directsByWrapper[direct.wrapper].push_back(index);
    for (auto [recordIndex, executor] :
         llvm::enumerate(result.mergedExecutors)) {
      if (executor.empty())
        continue;
      auto candidates = directsByWrapper.find(executor);
      if (candidates == directsByWrapper.end())
        continue;
      auto found = llvm::find_if(candidates->second, [&, &recordIndex =
                                                             recordIndex](
                                                         unsigned candidate) {
        return directFragments[candidate].actorSlot ==
                   result.mergedFragments[recordIndex].actor_slot &&
               directFragments[candidate].continuation ==
                   result.mergedFragments[recordIndex].continuation;
      });
      if (found == candidates->second.end())
        continue;
      const NativeDirectFragment *direct = &directFragments[*found];
      ownerIsCoordinator[recordIndex] = direct->instanceCoordinator;
      ownerFusionGroups[recordIndex] = direct->fusionGroup;
      SmallVector<uint32_t> ownedFragments;
      llvm::append_range(ownedFragments, direct->fragmentIDs);
      llvm::sort(ownedFragments);
      ownedFragments.erase(
          std::unique(ownedFragments.begin(), ownedFragments.end()),
          ownedFragments.end());
      ownerFragments[recordIndex] = std::move(ownedFragments);
    }

    result.ownerSubsumptionMasks.assign(
        result.mergedFragments.size(),
        llvm::APInt(std::max<size_t>(64, result.mergedFragments.size()), 0));
    std::optional<std::tuple<uint32_t, unsigned, unsigned>> overlap;
    // Only owner pairs that share a fragment can overlap. Visit exactly those
    // pairs, in the (first, second) order of an all-pairs scan.
    DenseMap<uint32_t, SmallVector<unsigned, 2>> fragmentOwnerLists;
    for (auto [owner, fragments] : llvm::enumerate(ownerFragments))
      for (uint32_t fragment : fragments)
        fragmentOwnerLists[fragment].push_back(owner);
    SmallVector<std::pair<unsigned, unsigned>> sharingPairs;
    for (const auto &[fragment, owners] : fragmentOwnerLists)
      for (size_t i = 0; i != owners.size(); ++i)
        for (size_t j = i + 1; j != owners.size(); ++j)
          sharingPairs.emplace_back(owners[i], owners[j]);
    llvm::sort(sharingPairs);
    sharingPairs.erase(std::unique(sharingPairs.begin(), sharingPairs.end()),
                       sharingPairs.end());
    for (auto [first, second] : sharingPairs) {
      auto shared = llvm::find_if(
          ownerFragments[first], [&, &second = second](uint32_t id) {
            return llvm::binary_search(ownerFragments[second], id);
          });
      unsigned coordinator = ownerIsCoordinator[first] ? first : second;
      unsigned exact = ownerIsCoordinator[first] ? second : first;
      bool certifiedPair =
          ownerIsCoordinator[first] != ownerIsCoordinator[second] &&
          ownerFusionGroups[coordinator] != UINT32_MAX &&
          ownerFusionGroups[coordinator] == ownerFusionGroups[exact];
      bool containsExact =
          certifiedPair &&
          llvm::all_of(ownerFragments[exact], [&](uint32_t fragment) {
            return llvm::binary_search(ownerFragments[coordinator], fragment);
          });
      // The only intentional overlap is a complete Tier-2 body nested in
      // its certified Tier-1 fusion coordinator. Partial overlap is not
      // executable ownership: both wrappers would execute the shared body.
      if (!containsExact) {
        overlap = std::tuple{*shared, first, second};
        break;
      }
      result.ownerSubsumptionMasks[coordinator].setBit(
          result.mergedFragments[exact].bit);
    }
    if (overlap) {
      auto [fragment, firstOwner, secondOwner] = *overlap;
      return module.emitError("eval fragment ")
             << fragment << " is covered by distinct direct owners "
             << firstOwner << " (" << result.mergedExecutors[firstOwner]
             << ") and " << secondOwner << " ("
             << result.mergedExecutors[secondOwner] << ")";
    }

    llvm::DenseMap<uint32_t, unsigned> fragmentOwners;
    for (unsigned owner = 0; owner != result.mergedFragments.size(); ++owner) {
      for (uint32_t fragment : ownerFragments[owner]) {
        auto [found, inserted] = fragmentOwners.try_emplace(fragment, owner);
        if (!inserted && ownerIsCoordinator[owner])
          found->second = owner;
      }
    }

    // Index outgoing dependencies once. An NBA stage reaches only activation
    // edges from its target resource node, and still needs the exact packed
    // range/descriptor overlap proof below (IEEE 1800-2023 4.4, 10.4.2).
    DenseMap<uint32_t, SmallVector<schedule::ComputeEdgeAttr>> outgoingEdges;
    DenseMap<uint32_t, SmallVector<schedule::ComputeEdgeAttr>> nbaActivations;
    for (Attribute attribute : computeGraph.getEdges()) {
      auto edge = cast<schedule::ComputeEdgeAttr>(attribute);
      switch (edge.getKind()) {
      case schedule::ComputeEdgeKind::Sensitivity:
      case schedule::ComputeEdgeKind::Resume:
      case schedule::ComputeEdgeKind::NBAStage:
        outgoingEdges[edge.getSource()].push_back(edge);
        break;
      case schedule::ComputeEdgeKind::NBAActivate:
        nbaActivations[edge.getSource()].push_back(edge);
        break;
      default:
        break;
      }
    }
    llvm::SmallDenseSet<uint32_t, 64> reachableNodes;
    SmallVector<uint32_t> pendingNodes;
    auto reachNode = [&](uint32_t node) {
      if (reachableNodes.insert(node).second)
        pendingNodes.push_back(node);
    };
    for (unsigned owner : closure)
      for (uint32_t fragment : ownerFragments[owner])
        reachNode(fragment);
    auto reachOwner = [&](uint32_t fragment) {
      auto target = fragmentOwners.find(fragment);
      if (target == fragmentOwners.end() ||
          !closure.insert(target->second).second)
        return;
      for (uint32_t owned : ownerFragments[target->second])
        reachNode(owned);
    };
    // Each newly reachable fragment is visited once, including other fragments
    // admitted through its owner. Cycles and duplicate edges cannot repeatedly
    // enqueue nodes; reaching an owner is independent of reaching its node.
    while (!pendingNodes.empty()) {
      auto outgoing = outgoingEdges.find(pendingNodes.pop_back_val());
      if (outgoing == outgoingEdges.end())
        continue;
      for (schedule::ComputeEdgeAttr edge : outgoing->second) {
        if (edge.getKind() != schedule::ComputeEdgeKind::NBAStage) {
          reachNode(edge.getTarget());
          reachOwner(edge.getTarget());
          continue;
        }
        auto activations = nbaActivations.find(edge.getTarget());
        if (activations == nbaActivations.end())
          continue;
        for (schedule::ComputeEdgeAttr activation : activations->second) {
          if (!rangesOverlap(edge.getResource(), activation.getResource()))
            continue;
          reachNode(activation.getTarget());
          reachOwner(activation.getTarget());
        }
      }
    }
    // Tier-1 execution contains these exact Tier-2 bodies, but generated
    // transitions still publish their exact identities.  Keep them in the
    // periodic promotion/transition closure while leaving only the complete
    // coordinator in the periodic entry set.
    SmallVector<unsigned> closureSnapshot(closure.begin(), closure.end());
    for (unsigned owner : closureSnapshot) {
      if (owner >= result.ownerSubsumptionMasks.size())
        continue;
      llvm::APInt members = result.ownerSubsumptionMasks[owner];
      while (!members.isZero()) {
        unsigned bit = members.countr_zero();
        closure.insert(bit);
        members.clearBit(bit);
      }
    }
    result.periodicClosureRecords.assign(closure.begin(), closure.end());
    llvm::sort(result.periodicClosureRecords);
  }

  if (result.ownerSubsumptionMasks.empty())
    result.ownerSubsumptionMasks.assign(
        result.mergedFragments.size(),
        llvm::APInt(std::max<size_t>(64, result.mergedFragments.size()), 0));

  result.rankedNodes =
      collectRankedNodes(module, result, stateLayout, staticFanoutPlan,
                         directFragments, computeGraph, activationInputs);

  // The dispatcher selects the lowest pending bit. Give it the same refined
  // dependence order as the helpers, including original-executor boundaries.
  // Otherwise a ready consumer in a later segment can outrank its producers
  // and force another activation even when the component is acyclic.
  // Preserve slots of clocked and unrepresented owners; this only permutes
  // Active combinational work (IEEE 1800-2023 4.5--4.7). SCC backedges remain
  // live and can republish earlier bits; this is not an execute-once promise.
  SmallVector<uint32_t> slots, ranked;
  for (const auto &node : result.rankedNodes)
    if (!node.clocked && node.owner != UINT32_MAX) {
      slots.push_back(node.owner);
      ranked.push_back(node.owner);
    }
  llvm::sort(slots);
  SmallVector<uint32_t> order(result.mergedFragments.size());
  std::iota(order.begin(), order.end(), 0u);
  for (auto [slot, owner] : llvm::zip_equal(slots, ranked))
    order[slot] = owner;
  reorderOwners(result, order);

  // Owners that resume in the Inactive region (IEEE 1800-2023 4.4.2.3) take
  // the highest bits, in their existing relative order. The lowest pending
  // bit is then deferred only when no Active owner is pending. They execute
  // alone: no executor may consume another owner's deferred activation.
  if (llvm::is_contained(result.deferredOwners, true)) {
    for (auto [owner, deferred] : llvm::enumerate(result.deferredOwners)) {
      if (!deferred)
        continue;
      uint32_t bit = result.mergedFragments[owner].bit;
      bool shared = !result.ownerSubsumptionMasks[owner].isZero() ||
                    llvm::any_of(result.ownerSubsumptionMasks,
                                 [&](const APInt &mask) { return mask[bit]; });
      if (shared)
        return module.emitError(
                   "a deferred eval owner cannot share an executor"),
               failure();
    }
    SmallVector<uint32_t> partition(result.mergedFragments.size());
    std::iota(partition.begin(), partition.end(), 0u);
    std::stable_partition(
        partition.begin(), partition.end(),
        [&](uint32_t owner) { return !result.deferredOwners[owner]; });
    reorderOwners(result, partition);
  }

  // Project graph-level NBA reachability onto exclusive generated owners.
  ArrayRef<talos_rt_static_nba_root> nbaRoots = staticNBAPlan.roots;
  result.nbaTaintWordCount = static_cast<uint32_t>((nbaRoots.size() + 63) / 64);
  result.recordNBATaintMasks.assign(
      result.mergedFragments.size(),
      SmallVector<uint64_t>(result.nbaTaintWordCount, 0));
  result.nbaTaintedRecords.resize(result.mergedFragments.size());
  if (result.mergedFragments.empty())
    return result;

  auto fillAllRoots = [&](MutableArrayRef<uint64_t> mask) {
    llvm::fill(mask, UINT64_MAX);
    if (!mask.empty() && (nbaRoots.size() & 63) != 0)
      mask.back() = (uint64_t{1} << (nbaRoots.size() & 63)) - 1;
  };
  if (!computeGraph) {
    for (unsigned index = 0; index != result.mergedFragments.size(); ++index) {
      fillAllRoots(result.recordNBATaintMasks[index]);
      result.nbaTaintedRecords.set(index);
    }
    return result;
  }

  llvm::DenseMap<uint32_t, SmallVector<uint64_t>> fragmentNBARoots;
  for (Attribute attribute : computeGraph.getNodes()) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute);
    if (!fragment)
      continue;
    auto &mask = fragmentNBARoots[fragment.getId()];
    mask.resize(result.nbaTaintWordCount, 0);
    for (Attribute raw : fragment.getEffects()) {
      auto effect = cast<schedule::ComputeEffectAttr>(raw);
      if (effect.getEffect() != schedule::ComputeEffectKind::NBA)
        continue;
      auto handle = stateLayout.storage.find(effect.getDescriptor());
      talos_rt_stable_handle_v1 decoded{};
      if (handle == stateLayout.storage.end() ||
          !talos_rt_stable_handle_decode(handle->second, &decoded) ||
          decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC) {
        fillAllRoots(mask);
        continue;
      }
      auto root = llvm::find_if(nbaRoots, [&](const auto &candidate) {
        return candidate.static_state == decoded.id;
      });
      if (root == nbaRoots.end()) {
        fillAllRoots(mask);
        continue;
      }
      size_t rootIndex = static_cast<size_t>(root - nbaRoots.begin());
      mask[rootIndex / 64] |= uint64_t{1} << (rootIndex % 64);
    }
  }
  // May-taint is a finite union lattice over NBA roots. Index reverse
  // dependencies once and revisit only predecessors of a changed fact.
  DenseMap<uint32_t, SmallVector<uint32_t>> predecessors;
  for (Attribute attribute : computeGraph.getEdges()) {
    auto edge = cast<schedule::ComputeEdgeAttr>(attribute);
    if (edge.getKind() == schedule::ComputeEdgeKind::Sensitivity ||
        edge.getKind() == schedule::ComputeEdgeKind::Resume ||
        edge.getKind() == schedule::ComputeEdgeKind::Spawn)
      predecessors[edge.getTarget()].push_back(edge.getSource());
  }
  SmallVector<uint32_t> pending;
  DenseSet<uint32_t> queued;
  for (const auto &entry : fragmentNBARoots)
    if (llvm::any_of(entry.second, [](uint64_t word) { return word != 0; })) {
      pending.push_back(entry.first);
      queued.insert(entry.first);
    }
  while (!pending.empty()) {
    uint32_t target = pending.pop_back_val();
    queued.erase(target);
    // Inserting a predecessor may rehash fragmentNBARoots.
    auto roots = fragmentNBARoots.lookup(target);
    for (uint32_t predecessor : predecessors.lookup(target)) {
      auto &source = fragmentNBARoots[predecessor];
      source.resize(result.nbaTaintWordCount, 0);
      bool changed = false;
      for (uint32_t word = 0; word != result.nbaTaintWordCount; ++word) {
        uint64_t merged = source[word] | roots[word];
        changed |= merged != source[word];
        source[word] = merged;
      }
      if (changed && queued.insert(predecessor).second)
        pending.push_back(predecessor);
    }
  }
  for (auto [recordIndex, executor] : llvm::enumerate(result.mergedExecutors)) {
    auto direct = llvm::find_if(directFragments, [&, &executor = executor,
                                                  &recordIndex = recordIndex](
                                                     const auto &candidate) {
      return candidate.wrapper == executor &&
             candidate.actorSlot ==
                 result.mergedFragments[recordIndex].actor_slot &&
             candidate.continuation ==
                 result.mergedFragments[recordIndex].continuation;
    });
    if (direct == directFragments.end()) {
      fillAllRoots(result.recordNBATaintMasks[recordIndex]);
      result.nbaTaintedRecords.set(recordIndex);
      continue;
    }
    for (uint32_t fragment : direct->fragmentIDs)
      if (auto roots = fragmentNBARoots.find(fragment);
          roots != fragmentNBARoots.end())
        for (uint32_t word = 0; word != result.nbaTaintWordCount; ++word)
          result.recordNBATaintMasks[recordIndex][word] |= roots->second[word];
    if (llvm::any_of(result.recordNBATaintMasks[recordIndex],
                     [](uint64_t word) { return word != 0; }))
      result.nbaTaintedRecords.set(recordIndex);
  }
  // LRM 4.9.4 and 10.4.2: local pending values belong to captured NBA
  // statements, never to ordinary current-state reads. Revalidate the source
  // graph revision and require complete writer coverage by non-bootstrap
  // generated continuations. A private batch certificate alone is insufficient.
  unsigned pendingCandidates = 0, pendingWriters = 0;
  unsigned pendingBootstrap = 0, pendingCheckpoint = 0, pendingTier2 = 0;
  unsigned pendingMissingOwner = 0, pendingMissingFragment = 0;
  if (activationInputs.sourceGraph == computeGraph &&
      activationInputs.completeNBAWriters &&
      staticNBAPlan.completeSourceWriters) {
    result.transaction.sourceGraph = computeGraph;
    for (auto [index, root] : llvm::enumerate(staticNBAPlan.roots)) {
      if (root.bit_width > 64 ||
          index >= staticNBAPlan.rootDescriptors.size() ||
          !staticNBAPlan.mergeSafeRoots[index] ||
          !staticNBAPlan.privateInfluenceRoots[index])
        continue;
      // runtimeQueueRoots certifies that a shared fallback queue is available;
      // it does not say the generated producer uses that queue. The lowering
      // certificate below must cover every source site with its actual fixed
      // capture form (LRM 4.9.4/10.4.2), including all outlined variants.
      ++pendingCandidates;
      uint64_t descriptor = staticNBAPlan.rootDescriptors[index];
      auto writers = activationInputs.nbaWriters.find(descriptor);
      if (writers == activationInputs.nbaWriters.end() ||
          writers->second.empty())
        continue;
      ++pendingWriters;
      NativeEvalTransactionRoot planned{
          descriptor,
          static_cast<uint32_t>(index),
          root.static_state,
          staticNBAPlan.generatedOffsets[index],
          root.bit_width,
          staticNBAPlan.generatedFixedWriteMasks[index],
          TALOS_RT_REGION_NBA,
          staticNBAPlan.trackTransients[index],
          writers->second,
          {},
          {}};
      for (const auto &site : staticNBAPlan.sites)
        if (site.root == index) {
          auto origin = staticNBAPlan.siteSemanticOrigins.find(site.site);
          planned.sites.push_back(
              origin == staticNBAPlan.siteSemanticOrigins.end()
                  ? site.site
                  : origin->second);
        }
      llvm::sort(planned.sites);
      planned.sites.erase(
          std::unique(planned.sites.begin(), planned.sites.end()),
          planned.sites.end());
      bool covered = llvm::all_of(planned.writerFragments, [&](uint32_t id) {
        bool found = false;
        bool matched = false;
        for (const auto &direct : directFragments) {
          if (!llvm::is_contained(direct.fragmentIDs, id))
            continue;
          matched = true;
          if (direct.initialActivation || direct.runtimeCheckpoint ||
              direct.tier2Convergence) {
            pendingBootstrap += direct.initialActivation;
            pendingCheckpoint += direct.runtimeCheckpoint;
            pendingTier2 += direct.tier2Convergence;
            continue;
          }
          auto owner = llvm::find(result.mergedExecutors, direct.wrapper);
          if (owner == result.mergedExecutors.end()) {
            ++pendingMissingOwner;
            continue;
          }
          planned.owners.push_back(
              static_cast<uint32_t>(owner - result.mergedExecutors.begin()));
          found = true;
        }
        pendingMissingFragment += !matched;
        return found;
      });
      if (!covered)
        continue;
      llvm::sort(planned.owners);
      planned.owners.erase(
          std::unique(planned.owners.begin(), planned.owners.end()),
          planned.owners.end());
      result.transaction.roots.push_back(std::move(planned));
    }
  }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos eval transaction source roots: "
                 << result.transaction.roots.size() << "/"
                 << staticNBAPlan.roots.size()
                 << " graph=" << (activationInputs.sourceGraph == computeGraph)
                 << " nba-writers=" << activationInputs.completeNBAWriters
                 << " complete-writers=" << staticNBAPlan.completeSourceWriters
                 << " candidates=" << pendingCandidates
                 << " writers=" << pendingWriters
                 << " writer-descriptors=" << activationInputs.nbaWriters.size()
                 << " bootstrap=" << pendingBootstrap
                 << " checkpoint=" << pendingCheckpoint
                 << " tier2=" << pendingTier2
                 << " missing-owner=" << pendingMissingOwner
                 << " missing-fragment=" << pendingMissingFragment << '\n';
  return result;
}

} // namespace talos::detail
