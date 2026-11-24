//===- NativeEvalRankAnalysisTest.cpp - Native eval ranking ===//
#include "talos/Analysis/NativeEvalRankAnalysis.h"
#include "talos/Runtime/ActivationOrder.h"
#include "gtest/gtest.h"
#include <algorithm>
#include <numeric>

using namespace talos::analysis;
using talos::runtime::ActivationOrder;

namespace {
NativeRankGraph graph(std::vector<NativeRankEdge> edges) {
  return {3,
          {{"a", 0, true, true}, {"b", 0, true, true}, {"c", 0, true, true}},
          std::move(edges)};
}
NativeEvalLayout layout() {
  return {{{"a", "helper"}, {"b", "helper"}, {"c", "helper"}}, {}, {}};
}
NativeRankCost measure(const std::vector<uint32_t> &order,
                       const NativeRankGraph &g) {
  std::vector<unsigned> pos(order.size());
  for (unsigned i = 0; i < order.size(); ++i)
    pos[order[i]] = i;
  std::set<unsigned> receivers;
  unsigned count = 0;
  for (auto [a, b] : g.edges)
    if (pos[b] <= pos[a]) {
      receivers.insert(b);
      ++count;
    }
  return {receivers.size(), count};
}
TEST(NativeEvalRanking, SharedHeuristicAndZ3MatchExhaustiveOracle) {
  if (!hasZ3NativeRankAnalysis())
    GTEST_SKIP();
  const std::vector<NativeRankEdge> candidates = {{0, 1}, {0, 2}, {1, 0},
                                                  {1, 2}, {2, 0}, {2, 1}};
  for (unsigned mask = 0; mask < 64; ++mask) {
    SCOPED_TRACE(mask);
    auto g = graph({{2, 2}});
    for (unsigned i = 0; i < candidates.size(); ++i)
      if (mask & (1u << i))
        g.edges.push_back(candidates[i]);
    std::sort(g.edges.begin(), g.edges.end());
    ActivationOrder base, solution;
    auto baseline = NativeEvalRankAnalysis::get(NativeRankStrategy::Heuristic)
                        .analyze(g, layout(), base);
    ASSERT_TRUE(static_cast<bool>(baseline));
    auto selected = NativeEvalRankAnalysis::get(NativeRankStrategy::Z3)
                        .analyze(g, layout(), solution);
    ASSERT_TRUE(static_cast<bool>(selected));
    auto best = measure(base.nodes, g);
    std::vector<unsigned> trial = {0, 1, 2};
    do {
      bool admissible = true;
      for (unsigned i = 0; i < 3; ++i)
        admissible &=
            base.componentOf[base.nodes[i]] == base.componentOf[trial[i]];
      if (admissible)
        best = std::min(best, measure(trial, g));
    } while (std::next_permutation(trial.begin(), trial.end()));
    EXPECT_TRUE(selected->proven);
    EXPECT_EQ(baseline->selected, measure(base.nodes, g));
    EXPECT_EQ(selected->selected, best);
    EXPECT_EQ(measure(solution.nodes, g), best);
    EXPECT_EQ(solution.feedback.size(), best.second);
    if (best == baseline->selected)
      EXPECT_EQ(solution.nodes, base.nodes);
  }
}
TEST(NativeEvalRanking, InvalidInputsLeavePublishedOrderIntact) {
  auto g = graph({{0, 1}});
  ActivationOrder order;
  auto &analysis = NativeEvalRankAnalysis::get(NativeRankStrategy::Heuristic);
  auto ok = analysis.analyze(g, {}, order);
  ASSERT_TRUE(static_cast<bool>(ok));
  auto original = order.nodes;
  EXPECT_FALSE(NativeEvalRankAnalysis::applyOrder(order, g.edges, {0, 0, 1}));
  EXPECT_EQ(original, order.nodes);
  g.edges.emplace_back(1, 3);
  auto invalid = analysis.analyze(g, {}, order);
  EXPECT_FALSE(static_cast<bool>(invalid));
  llvm::consumeError(invalid.takeError());
  EXPECT_EQ(original, order.nodes);
}
TEST(NativeEvalRanking, PreserveForwardingChainAndCheckpoint) {
  if (!hasZ3NativeRankAnalysis())
    GTEST_SKIP();
  auto g = graph({{0, 1}, {1, 0}, {1, 2}, {2, 0}});
  auto certificates = layout();
  certificates.chains.insert({"a", "b", "c"});
  ActivationOrder order;
  auto check = [&] {
    auto r = NativeEvalRankAnalysis::get(NativeRankStrategy::Z3)
                 .analyze(g, certificates, order);
    ASSERT_TRUE(static_cast<bool>(r));
    EXPECT_EQ(r->selected, (NativeRankCost{1, 2}));
    EXPECT_EQ(order.nodes, (std::vector<uint32_t>{0, 1, 2}));
  };
  check();
  certificates.chains.clear();
  g.units[1].movable = false;
  check();
  g.units[1].movable = true;
  certificates.helpers.erase("b");
  check();
}
TEST(NativeEvalRanking, LoweringMustRetainCertifiedExecutorsAndChains) {
  auto expected = layout();
  expected.chains.insert({"a", "b"});
  expected.unconditional.insert("a");
  auto trial = expected;
  trial.helpers["a"] = "another-helper";
  EXPECT_TRUE(trial.preserves(expected));
  trial.unconditional.clear();
  EXPECT_FALSE(trial.preserves(expected));
  trial = expected;
  trial.chains = {{"b", "a"}};
  EXPECT_FALSE(trial.preserves(expected));
  trial = expected;
  trial.runtimeCalendar = !expected.runtimeCalendar;
  EXPECT_FALSE(trial.preserves(expected));
  trial = expected;
  trial.helpers.erase("c");
  EXPECT_FALSE(trial.preserves(expected));
}
} // namespace
