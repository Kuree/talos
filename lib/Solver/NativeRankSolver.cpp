//===- NativeRankSolver.cpp - Native eval ranking ===//
#include "talos/Solver/NativeRankSolver.h"
#include "llvm/ADT/STLExtras.h"
#include <algorithm>
#include <map>
#include <numeric>
#include <tuple>
#ifdef TALOS_ENABLE_Z3
#include "Z3Support.h"
#include <z3++.h>
#endif
using namespace talos::solver;
using llvm::ArrayRef;
using Order = std::vector<uint32_t>;
RankCost talos::solver::backwardWakeCost(ArrayRef<RankEdge> edges,
                                         ArrayRef<uint32_t> pos,
                                         ArrayRef<uint8_t> fixed) {
  std::vector<uint8_t> received(pos.size());
  unsigned receivers = 0, backward = 0;
  for (auto [a, b] : edges)
    if (pos[a] >= pos[b]) {
      ++backward;
      if ((fixed.empty() || !fixed[b]) && !received[b]) {
        received[b] = true;
        ++receivers;
      }
    }
  return {receivers, backward};
}
llvm::Expected<bool>
talos::solver::minimizeRankPermutation(ArrayRef<RankSlot> run,
                                       ArrayRef<RankEdge> edges,
                                       ArrayRef<Order> chains, Order &result) {
  result.resize(run.size());
  std::iota(result.begin(), result.end(), 0u);
#ifndef TALOS_ENABLE_Z3
  return llvm::createStringError("native rank solver unavailable");
#else
  for (auto [a, b] : edges)
    if (a >= run.size() || b >= run.size())
      return llvm::createStringError("invalid native rank interval edge");
  for (const auto &chain : chains)
    if (chain.empty() ||
        llvm::any_of(chain, [&](auto v) { return v >= run.size(); }))
      return llvm::createStringError("invalid native forwarding chain");
  std::vector<uint8_t> fixed;
  for (const auto &slot : run)
    fixed.push_back(slot.hasFixedBackwardWake);
  auto slotKey = [](const RankSlot &slot) {
    return std::tie(slot.repeatable, slot.twoState, slot.convergence);
  };
  const Order baseline = result;
  auto best = backwardWakeCost(edges, baseline, fixed);
  std::vector<RankEdge> loops, hard;
  for (auto [a, b] : edges) {
    if (a == b)
      loops.emplace_back(a, b);
    if (a < b && !run[b].repeatable)
      hard.emplace_back(a, b);
  }
  auto floor = backwardWakeCost(loops, baseline, fixed);
  if (best == floor)
    return true;
  // Bound formula construction as well as SAT work. Larger intervals retain
  // their complete, legal heuristic permutation.
  if (run.size() > 512)
    return false;
  Order chosen = baseline;
  std::vector<uint8_t> linked(run.size()), active(run.size());
  for (const auto &ch : chains)
    for (auto v : ch)
      linked[v] = active[v] = true;
  for (auto [a, b] : edges)
    if (a != b)
      active[a] = active[b] = true;
  // Slots of the same evaluation form may exchange their occupants. A
  // forwarding chain additionally needs one translation in its own helper.
  std::map<std::tuple<bool, bool, bool>, Order> slots;
  for (unsigned i : baseline)
    slots[slotKey(run[i])].push_back(i);
  // Supply a deterministic incumbent even when a hard SAT query exhausts
  // its budget. Only strict improvements can displace the heuristic.
  unsigned attempts = 0;
  for (const auto &[key, group] : slots)
    for (unsigned a : group)
      for (unsigned b : group) {
        if (a >= b || linked[a] || linked[b] || attempts >= 8192)
          continue;
        ++attempts;
        std::swap(chosen[a], chosen[b]);
        auto next = backwardWakeCost(edges, chosen, fixed);
        if (next < best &&
            llvm::all_of(
                hard,
                [&](auto e) { return chosen[e.first] < chosen[e.second]; }))
          best = next;
        else
          std::swap(chosen[a], chosen[b]);
      }
  unsigned width = 1;
  while ((1u << width) < run.size())
    ++width;
#ifdef TALOS_Z3_SINGLE_THREADED
  std::lock_guard<std::mutex> lock(detail::getZ3Mutex());
#endif
  try {
    z3::context ctx;
    z3::solver solver(ctx, "QF_FD");
    // Resource units, rather than a wall-clock timeout, keep compilation
    // deterministic under host load.

    // Independent filler vertices need no SMT variable in the permutation.
    // They take the unused slots of their own type when extracting the model.
    z3::expr_vector ranks(ctx), distinct(ctx), edgeBits(ctx), ownerBits(ctx);
    for (unsigned i : baseline) {
      ranks.push_back(ctx.bv_const(("r" + std::to_string(i)).c_str(), width));
      if (!active[i])
        continue;
      distinct.push_back(ranks[i]);
      z3::expr_vector choices(ctx);
      for (unsigned j : slots.at(slotKey(run[i])))
        if (!linked[i] || run[i].helper == run[j].helper)
          choices.push_back(ranks[i] == ctx.bv_val(j, width));
      solver.add(z3::mk_or(choices));
    }
    if (distinct.size() > 1)
      solver.add(z3::distinct(distinct));
    for (const auto &ch : chains) {
      unsigned first = *std::min_element(ch.begin(), ch.end());
      for (auto v : ch)
        if (v != first)
          solver.add(z3::ult(ranks[first], ranks[v]) &&
                     ranks[v] == ranks[first] + ctx.bv_val(v - first, width));
    }
    std::map<unsigned, z3::expr_vector> incoming;
    for (auto [a, b] : edges) {
      z3::expr back = a == b ? ctx.bool_val(true) : z3::uge(ranks[a], ranks[b]);
      edgeBits.push_back(back);
      if (!fixed[b])
        incoming.try_emplace(b, ctx).first->second.push_back(back);
    }
    for (auto [a, b] : hard)
      solver.add(z3::ult(ranks[a], ranks[b]));
    for (auto &[v, bits] : incoming)
      ownerBits.push_back(z3::mk_or(bits));
    // After proving the receiver minimum, constrain it before minimizing
    // edges. A fresh solver gives each bound its own deterministic work limit.
    bool proven = true;
    for (bool primary : {true, false}) {
      unsigned low = primary ? floor.first : floor.second,
               high = primary ? best.first : best.second;
      auto &bits = primary ? ownerBits : edgeBits;
      while (low < high) {
        unsigned mid = low + (high - low) / 2;
        z3::solver query(ctx, "QF_FD");
        query.set("rlimit", 2000000u);
        query.add(solver.assertions());
        query.add(z3::atmost(bits, mid));
        auto status = query.check();
        if (status == z3::unknown) {
          proven = false;
          break;
        }
        if (status == z3::unsat) {
          low = mid + 1;
          continue;
        }
        auto model = query.get_model();
        std::vector<uint8_t> used(run.size());
        for (unsigned i : baseline)
          if (active[i]) {
            chosen[i] = model.eval(ranks[i], true).get_numeral_uint();
            if (chosen[i] >= run.size() || used[chosen[i]])
              return llvm::createStringError("invalid Z3 rank assignment");
            used[chosen[i]] = true;
          }
        for (auto &[key, group] : slots) {
          auto it = group.begin();
          for (unsigned i : group)
            if (!active[i]) {
              while (it != group.end() && used[*it])
                ++it;
              if (it == group.end())
                return llvm::createStringError(
                    "no compatible native slot for rank assignment");
              chosen[i] = *it++;
            }
        }
        best = backwardWakeCost(edges, chosen, fixed);
        high = primary ? best.first : best.second;
      }
      if (!proven)
        break;
      if (high < bits.size())
        solver.add(z3::atmost(bits, high));
    }
    // Recheck the extracted (or bounded) assignment independently of Z3.
    std::vector<uint8_t> assigned(run.size());
    for (unsigned i : baseline) {
      unsigned j = chosen[i];
      if (j >= run.size() || assigned[j] ||
          slotKey(run[i]) != slotKey(run[j]) ||
          (linked[i] && run[i].helper != run[j].helper))
        return llvm::createStringError(
            "native solver changed an evaluator slot");
      assigned[j] = true;
    }
    for (const auto &chain : chains) {
      int64_t offset = int64_t(chosen[chain.front()]) - chain.front();
      for (unsigned v : chain)
        if (int64_t(chosen[v]) - v != offset)
          return llvm::createStringError(
              "native solver broke a forwarding chain");
    }
    for (auto [a, b] : hard)
      if (chosen[a] >= chosen[b])
        return llvm::createStringError(
            "native solver reversed a protected wake");
    if (best < backwardWakeCost(edges, baseline, fixed))
      for (unsigned i : baseline)
        result[chosen[i]] = i;
    return proven;
  } catch (const z3::exception &e) {
    return llvm::createStringError("native rank solver: %s", e.msg());
  }
#endif
}
bool talos::solver::nativeRankSolverAvailable() {
#ifdef TALOS_ENABLE_Z3
  return true;
#else
  return false;
#endif
}
