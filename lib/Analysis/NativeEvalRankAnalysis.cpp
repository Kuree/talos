//===- NativeEvalRankAnalysis.cpp - Native eval ranking ===//
#include "talos/Analysis/NativeEvalRankAnalysis.h"
#include "talos/Runtime/ActivationOrder.h"
#include "talos/Solver/NativeRankSolver.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"
#include <algorithm>
#include <tuple>

using namespace talos::analysis;
using llvm::ArrayRef;
using llvm::Expected;
using talos::runtime::ActivationOrder;

bool NativeRankUnit::operator==(const NativeRankUnit &r) const {
  return std::tie(executor, island, movable, repeatable, twoState,
                  convergence) == std::tie(r.executor, r.island, r.movable,
                                           r.repeatable, r.twoState,
                                           r.convergence);
}
bool NativeRankGraph::operator==(const NativeRankGraph &r) const {
  return size == r.size && units == r.units && edges == r.edges;
}
bool NativeEvalLayout::preserves(const NativeEvalLayout &required) const {
  if (runtimeCalendar != required.runtimeCalendar)
    return false;
  for (const auto &entry : required.helpers)
    if (!helpers.count(entry.first))
      return false;
  return std::includes(chains.begin(), chains.end(), required.chains.begin(),
                       required.chains.end()) &&
         std::includes(unconditional.begin(), unconditional.end(),
                       required.unconditional.begin(),
                       required.unconditional.end());
}
Expected<NativeRankResult>
NativeEvalRankAnalysis::analyze(const NativeRankGraph &g,
                                const NativeEvalLayout &layout,
                                ActivationOrder &order) const {
  ActivationOrder candidate;
  if (!ActivationOrder::build(g.size, g.edges, candidate))
    return llvm::createStringError("invalid native rank edge");
  // Topology-only heuristic callers may supply unsorted or repeated edges.
  // Certified costs and trial identities use a unique edge inventory.
  if (!g.units.empty() &&
      (!std::is_sorted(g.edges.begin(), g.edges.end()) ||
       std::adjacent_find(g.edges.begin(), g.edges.end()) != g.edges.end()))
    return llvm::createStringError(
        "native rank capabilities require canonical edges");
  auto result = refine(g, layout, candidate);
  if (result)
    order = std::move(candidate);
  return result;
}
bool NativeEvalRankAnalysis::applyOrder(ActivationOrder &order,
                                        ArrayRef<NativeRankEdge> edges,
                                        ArrayRef<uint32_t> selected) {
  if (selected.size() != order.nodes.size())
    return false;
  std::vector<unsigned> pos(selected.size(), UINT32_MAX);
  for (unsigned i = 0; i < selected.size(); ++i) {
    auto v = selected[i];
    if (v >= selected.size() || pos[v] != UINT32_MAX ||
        order.componentOf[v] != order.componentOf[order.nodes[i]])
      return false;
    pos[v] = i;
  }
  std::vector<NativeRankEdge> feedback;
  for (auto [a, b] : edges) {
    if (a >= pos.size() || b >= pos.size())
      return false;
    if (pos[a] >= pos[b])
      feedback.emplace_back(a, b);
  }
  order.nodes = std::vector<uint32_t>(selected.begin(), selected.end());
  order.feedback = std::move(feedback);
  return true;
}
namespace {
using Order = std::vector<uint32_t>;
Order positions(ArrayRef<uint32_t> order) {
  Order pos(order.size());
  for (size_t i = 0; i < order.size(); ++i)
    pos[order[i]] = i;
  return pos;
}
class HeuristicRankAnalysis final : public NativeEvalRankAnalysis {
public:
  Expected<NativeRankResult> refine(const NativeRankGraph &g,
                                    const NativeEvalLayout &,
                                    ActivationOrder &order) const override {
    std::set<unsigned> receivers;
    for (auto [from, to] : order.feedback)
      receivers.insert(to);
    NativeRankCost initial{receivers.size(), order.feedback.size()};
    return NativeRankResult{initial, initial, false};
  }
};
constexpr unsigned absent = UINT32_MAX;
struct Intervals {
  std::vector<Order> runs;
  Order membership;
};
Intervals intervals(const NativeRankGraph &g, const NativeEvalLayout &layout,
                    const ActivationOrder &base,
                    const std::set<std::string> &pinned) {
  Intervals r;
  r.membership.resize(g.units.size(), absent);
  unsigned previous = absent;
  for (unsigned id : base.nodes) {
    const auto &n = g.units[id];
    if (!n.movable || !layout.helpers.count(n.executor) ||
        pinned.count(n.executor)) {
      previous = absent;
      continue;
    }
    if (previous == absent ||
        base.componentOf[previous] != base.componentOf[id] ||
        g.units[previous].island != n.island)
      r.runs.emplace_back();
    r.membership[id] = r.runs.size() - 1;
    r.runs.back().push_back(id);
    previous = id;
  }
  return r;
}

class Z3RankAnalysis final : public NativeEvalRankAnalysis {
public:
  Expected<NativeRankResult> refine(const NativeRankGraph &g,
                                    const NativeEvalLayout &layout,
                                    ActivationOrder &base) const override {
    if (!talos::solver::nativeRankSolverAvailable())
      return llvm::createStringError(
          "native rank strategy 'z3' requires TALOS_ENABLE_Z3");
    if (g.units.size() != g.size)
      return llvm::createStringError("missing native rank capabilities");
    Order pos = positions(base.nodes), selected = base.nodes;
    auto initial = talos::solver::backwardWakeCost(g.edges, pos);
    std::map<std::string, unsigned> ids;
    std::set<std::string> pinned;
    for (unsigned v : base.nodes) {
      const auto &name = g.units[v].executor;
      if (!name.empty() && !ids.emplace(name, v).second)
        pinned.insert(name);
    }
    Intervals runs;
    bool changed;
    do {
      runs = intervals(g, layout, base, pinned);
      changed = false;
      for (const auto &ch : layout.chains) {
        unsigned range = absent;
        bool crosses = false;
        for (auto &name : ch) {
          auto it = ids.find(name);
          if (it == ids.end() || runs.membership[it->second] == absent) {
            crosses = true;
            break;
          }
          auto next = runs.membership[it->second];
          if (range != absent && range != next) {
            crosses = true;
            break;
          }
          range = next;
        }
        if (crosses)
          for (auto &name : ch)
            changed |= pinned.insert(name).second;
      }
    } while (changed);
    std::vector<std::vector<Order>> chains(runs.runs.size());
    for (const auto &ch : layout.chains) {
      if (ch.empty() || pinned.count(ch.front()))
        continue;
      auto k = runs.membership[ids.at(ch.front())];
      Order members;
      for (auto &name : ch)
        members.push_back(pos[ids.at(name)] - pos[runs.runs[k].front()]);
      chains[k].push_back(std::move(members));
    }
    std::vector<std::vector<NativeRankEdge>> local(runs.runs.size());
    std::vector<uint8_t> forced(g.units.size());
    for (auto [a, b] : g.edges) {
      unsigned k = runs.membership[a];
      if (k != absent && k == runs.membership[b]) {
        auto offset = pos[runs.runs[k].front()];
        local[k].emplace_back(pos[a] - offset, pos[b] - offset);
      } else if (pos[a] >= pos[b])
        forced[b] = true;
    }
    bool proven = true;
    for (unsigned k = 0; k < runs.runs.size(); ++k) {
      const auto &run = runs.runs[k];
      if (local[k].empty() || run.size() < 2)
        continue;
      std::map<std::string, unsigned> helpers;
      std::vector<talos::solver::RankSlot> slots;
      for (auto v : run) {
        const auto &unit = g.units[v];
        unsigned helper =
            helpers
                .try_emplace(layout.helpers.at(unit.executor), helpers.size())
                .first->second;
        slots.push_back({unit.repeatable, unit.twoState, unit.convergence,
                         bool(forced[v]), helper});
      }
      Order permutation;
      auto exact = talos::solver::minimizeRankPermutation(
          slots, local[k], chains[k], permutation);
      if (!exact)
        return exact.takeError();
      proven &= *exact;
      for (unsigned i = 0; i < run.size(); ++i)
        selected[pos[run.front()] + i] = run[permutation[i]];
    }
    auto after = positions(selected);
    for (auto [a, b] : g.edges)
      if (pos[a] < pos[b] && after[a] >= after[b] && !g.units[b].repeatable)
        return llvm::createStringError(
            "native rank order violates a protected wake");
    auto finalCost = talos::solver::backwardWakeCost(g.edges, after);
    if (finalCost < initial && !applyOrder(base, g.edges, selected))
      return llvm::createStringError("invalid native rank permutation");
    return NativeRankResult{initial, std::min(initial, finalCost), proven};
  }
};
} // namespace
bool talos::analysis::hasZ3NativeRankAnalysis() {
  return talos::solver::nativeRankSolverAvailable();
}
const NativeEvalRankAnalysis &
NativeEvalRankAnalysis::get(NativeRankStrategy strategy) {
  static const HeuristicRankAnalysis heuristic;
  static const Z3RankAnalysis z3;
  switch (strategy) {
  case NativeRankStrategy::Heuristic:
    return heuristic;
  case NativeRankStrategy::Z3:
    return z3;
  }
  llvm_unreachable("invalid native rank strategy");
}
