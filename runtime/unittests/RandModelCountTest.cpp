#include "../lib/RandModelCount.h"

#include "gtest/gtest.h"

#include <optional>
#include <set>

using talos::random::BooleanCircuit;
using talos::random::PlanOpcode;
using talos::runtime::ModelCount;
using talos::runtime::ModelCounter;
using talos::runtime::ModelSampler;
using ID = BooleanCircuit::ID;

namespace {

class RandModelCountTest : public ::testing::Test {
protected:
  ID bit(unsigned index) {
    return context.input(PlanOpcode::RandomBit, index, index);
  }

  std::vector<ID> numeral(uint64_t value, unsigned width) {
    std::vector<ID> result(width);
    for (unsigned bit = 0; bit != width; ++bit)
      result[bit] = bit < 64 && ((value >> bit) & 1);
    return result;
  }

  const std::vector<ID> &packed(const std::vector<ID> &bits) { return bits; }

  ID equal(const std::vector<ID> &bits, const std::vector<ID> &value) {
    ID match = 1;
    for (unsigned bit = 0; bit != bits.size(); ++bit)
      match = context.conjunction(
          match, context.exclusiveOr(bits[bit], value[bit]) ^ 1);
    return match;
  }

  BooleanCircuit context;
};

TEST_F(RandModelCountTest, CountsAndRanksMatchExhaustiveIntegerArithmetic) {
  std::vector<ID> variables, xBits, yBits;
  for (unsigned index = 0; index != 4; ++index) {
    xBits.push_back(bit(index * 2));
    yBits.push_back(bit(index * 2 + 1));
    variables.push_back(xBits.back());
    variables.push_back(yBits.back());
  }
  // The fixture's small nonlinear relation is independently enumerated
  // into Boolean cubes, preserving the original exact rank/count comparison.
  ID predicate = 0;
  for (unsigned a = 0; a != 16; ++a)
    for (unsigned b = 0; b != 16; ++b)
      if (((a * b) & 15) % 7 == 3 && a >= 2 && b < 14 && a != b)
        predicate = context.disjunction(
            predicate, context.conjunction(equal(xBits, numeral(a, 4)),
                                           equal(yBits, numeral(b, 4))));
  std::set<unsigned> expected;
  for (unsigned a = 0; a != 16; ++a)
    for (unsigned b = 0; b != 16; ++b)
      if (((a * b) & 15) % 7 == 3 && a >= 2 && b < 14 && a != b)
        expected.insert(a | (b << 4));
  ModelCounter counter(context, variables);
  ASSERT_TRUE(counter.build(predicate));
  ASSERT_EQ(counter.count().compare(ModelCount(expected.size())), 0);
  std::set<unsigned> actual;
  for (unsigned rank = 0; rank != expected.size(); ++rank) {
    std::vector<bool> value = counter.assignment(ModelCount(rank));
    unsigned a = 0, b = 0;
    for (unsigned index = 0; index != 4; ++index) {
      a |= unsigned(value[index * 2]) << index;
      b |= unsigned(value[index * 2 + 1]) << index;
    }
    ASSERT_TRUE(actual.insert(a | (b << 4)).second);
  }
  EXPECT_EQ(actual, expected);
}

TEST_F(RandModelCountTest, CountsWideImplicationIncludingItsSingleton) {
  // The LRM 18.5.9 example widened beyond two words: 2^130 unconstrained
  // guard-false combinations and exactly one guard-true combination.
  std::vector<ID> variables;
  for (unsigned index = 0; index != 131; ++index)
    variables.push_back(bit(index));
  ID guard = variables.back();
  std::vector<ID> data(variables.begin(), variables.end() - 1);
  ID predicate =
      context.disjunction(guard ^ 1, equal(packed(data), numeral(0, 130)));
  ModelCounter counter(context, variables);
  ASSERT_TRUE(counter.build(predicate));
  ModelCount expected = ModelCount::powerOfTwo(130);
  expected.add(ModelCount(1));
  ASSERT_EQ(counter.count().compare(expected), 0);
  auto zero = counter.assignment(ModelCount());
  EXPECT_EQ(std::count(zero.begin(), zero.end(), true), 0);
  auto singleton = counter.assignment(ModelCount(1));
  EXPECT_TRUE(singleton.back());
  EXPECT_EQ(std::count(singleton.begin(), singleton.end() - 1, true), 0);
  auto last = counter.assignment(ModelCount::powerOfTwo(130));
  EXPECT_FALSE(last.back());
  EXPECT_EQ(std::count(last.begin(), last.end() - 1, true), 130);
}

TEST(RandModelSamplerTest,
     OwnsProjectedRanksAfterCounterAndCircuitDestruction) {
  std::optional<ModelSampler> sampler;
  {
    BooleanCircuit circuit;
    std::vector<ID> bits;
    for (unsigned bit = 0; bit != 7; ++bit)
      bits.push_back(circuit.input(PlanOpcode::RandomBit, bit, bit));
    // Project away bit 2 from b0 -> (b1 && !b2), and bit 4 from
    // b3 != b4. The remaining legal choices are (!b0 || b1) and free b3.
    ID predicate = circuit.conjunction(
        circuit.disjunction(bits[0] ^ 1,
                            circuit.conjunction(bits[1], bits[2] ^ 1)),
        circuit.exclusiveOr(bits[3], bits[4]));
    ModelCounter counter(circuit, bits);
    ASSERT_TRUE(counter.build(predicate));
    std::vector<bool> values(7), fixed(7);
    values[5] = fixed[5] = true;
    counter.restrict(values, fixed);
    counter.project({true, true, false, true, false, false, false});
    sampler = counter.sampler();
    ASSERT_TRUE(sampler);
    ASSERT_TRUE(counter.constrain(0));
    EXPECT_TRUE(counter.count().zero());
    auto empty = counter.sampler();
    ASSERT_TRUE(empty);
    EXPECT_LT(empty->storageBytes(), counter.storageBytes());
    EXPECT_FALSE(counter.sampler(0));
    EXPECT_TRUE(counter.sampler(empty->storageBytes()));
  }
  ASSERT_EQ(sampler->count().compare(ModelCount(6)), 0);
  std::set<unsigned> actual;
  for (unsigned rank = 0; rank != 6; ++rank) {
    auto bits = sampler->assignment(ModelCount(rank));
    unsigned value = 0;
    for (unsigned bit = 0; bit != bits.size(); ++bit)
      value |= unsigned(bits[bit]) << bit;
    EXPECT_TRUE(sampler->contains(bits));
    EXPECT_TRUE(actual.insert(value).second);
  }
  EXPECT_EQ(actual, (std::set<unsigned>{32, 34, 35, 40, 42, 43}));
}

TEST(RandModelSamplerTest, OwnsArbitraryPrecisionFullCube) {
  std::optional<ModelSampler> sampler;
  {
    BooleanCircuit circuit;
    std::vector<ID> bits;
    for (unsigned bit = 0; bit != 130; ++bit)
      bits.push_back(circuit.input(PlanOpcode::RandomBit, bit, bit));
    ModelCounter counter(circuit, bits);
    ASSERT_TRUE(counter.build(1));
    sampler = counter.sampler();
  }
  EXPECT_EQ(sampler->count().compare(ModelCount::powerOfTwo(130)), 0);
  ModelCount last = sampler->count();
  last.subtract(ModelCount(1));
  auto bits = sampler->assignment(last);
  EXPECT_EQ(std::count(bits.begin(), bits.end(), true), 130);
  bits = sampler->assignment(ModelCount());
  EXPECT_EQ(std::count(bits.begin(), bits.end(), true), 0);
}

TEST_F(RandModelCountTest, FullWideCubeAndRejectionSamplingPreservePrecision) {
  std::vector<ID> variables;
  for (unsigned index = 0; index != 4096; ++index)
    variables.push_back(bit(index));
  ModelCounter counter(context, variables);
  ASSERT_TRUE(counter.build(1));
  ModelCount count = ModelCount::powerOfTwo(4096);
  ASSERT_EQ(counter.count().compare(count), 0);
  ModelCount maximum = count;
  maximum.subtract(ModelCount(1));
  auto last = counter.assignment(maximum);
  EXPECT_EQ(std::count(last.begin(), last.end(), true), 4096);
  talos_rt_random_state_v1 state{71, 15};
  EXPECT_TRUE(ModelCount::randomBelow(ModelCount(1), state).zero());
  EXPECT_EQ(state.state, 71u);
  // A cardinality just above a power of two exercises repeated rejection,
  // carries, leading-word masks, and draws wider than the PCG state.
  ModelCount bound = ModelCount::powerOfTwo(129);
  bound.add(ModelCount(13));
  auto sameState = state;
  for (unsigned index = 0; index != 256; ++index) {
    ModelCount rank = ModelCount::randomBelow(bound, state);
    EXPECT_LT(rank.compare(bound), 0);
    EXPECT_EQ(rank.compare(ModelCount::randomBelow(bound, sameState)), 0);
  }
  EXPECT_EQ(state.state, sameState.state);
}

TEST_F(RandModelCountTest, ProjectionCountsChoicesIndependentlyOfCompletions) {
  std::vector<ID> variables;
  for (unsigned index = 0; index != 131; ++index)
    variables.push_back(bit(index));
  std::vector<ID> data(variables.begin(), variables.end() - 1);
  ID predicate = context.disjunction(variables.back() ^ 1,
                                     equal(packed(data), numeral(0, 130)));
  std::vector<bool> keep(variables.size(), false);
  keep.back() = true;
  for (unsigned selected = 0; selected != 2; ++selected) {
    ModelCounter counter(context, variables);
    ASSERT_TRUE(counter.build(predicate));
    counter.project(keep);
    ASSERT_EQ(counter.count().compare(ModelCount(2)), 0);
    auto value = counter.assignment(ModelCount(selected));
    ASSERT_EQ(value.back(), selected != 0);
    counter.restrict(value, keep);
    EXPECT_EQ(counter.count().compare(selected ? ModelCount(1)
                                               : ModelCount::powerOfTwo(130)),
              0);
    auto completion = counter.assignment(ModelCount());
    EXPECT_EQ(completion.back(), selected != 0);
    EXPECT_EQ(std::count(completion.begin(), completion.end() - 1, true), 0);
  }
}

// An exported decision diagram names both cofactors of each node in its
// gates, so importing it needs no cofactor walk.
TEST_F(RandModelCountTest, DecisionReadsExportedDiagramCofactors) {
  std::vector<ID> variables;
  for (unsigned index = 0; index != 6; ++index)
    variables.push_back(bit(index));
  ID predicate =
      context.disjunction(context.exclusiveOr(variables[0], variables[3]),
                          context.conjunction(variables[1], variables[4] ^ 1));
  predicate = context.conjunction(
      predicate, context.disjunction(variables[2], variables[5]));
  ModelCounter counter(context, variables);
  ASSERT_TRUE(counter.build(predicate));
  BooleanCircuit exported;
  std::vector<ID> inputs;
  for (unsigned index = 0; index != 6; ++index)
    inputs.push_back(exported.input(PlanOpcode::RandomBit, index, index));
  ID root = counter.exportDiagram(exported, inputs);
  std::vector<ID> pending{root};
  std::set<ID> seen;
  unsigned decisions = 0;
  while (!pending.empty()) {
    ID id = pending.back();
    pending.pop_back();
    if (id <= 1 || !seen.insert(id).second)
      continue;
    uint32_t variable = exported.firstVariable(id);
    ID low = 0, high = 0;
    ASSERT_TRUE(exported.decision(id, variable, low, high));
    EXPECT_EQ(low, exported.cofactor(id, variable, false));
    EXPECT_EQ(high, exported.cofactor(id, variable, true));
    ++decisions;
    pending.push_back(low);
    pending.push_back(high);
  }
  EXPECT_GT(decisions, 6u);
  // A gate over arithmetic, not a decision on its first input, is declined.
  ID mixed = exported.exclusiveOr(inputs[0], inputs[1]);
  ID low = 0, high = 0;
  EXPECT_FALSE(
      exported.decision(exported.conjunction(mixed, inputs[2]), 0, low, high));
}

// Counts keep two words inline and move wider values to the heap and back.
TEST_F(RandModelCountTest, CountsCrossInlineStorage) {
  ModelCount half = ModelCount::powerOfTwo(127);
  ModelCount wide = half;
  wide.add(half);
  EXPECT_EQ(wide.compare(ModelCount::powerOfTwo(128)), 0);
  EXPECT_EQ(wide.bitWidth(), 129u);
  EXPECT_EQ(wide.word(2), 1u);
  ModelCount product = wide.multiplied(wide);
  EXPECT_EQ(product.compare(ModelCount::powerOfTwo(256)), 0);
  EXPECT_EQ(product.divided(wide).compare(wide), 0);
  product.subtract(ModelCount::powerOfTwo(256));
  EXPECT_TRUE(product.zero());
  wide.subtract(half);
  EXPECT_EQ(wide.compare(half), 0);
  EXPECT_EQ(wide.word(1), uint64_t{1} << 63);
  EXPECT_EQ(wide.word(2), 0u);
  EXPECT_EQ(half.shifted(70).compare(ModelCount::powerOfTwo(197)), 0);
}

// Evaluate all six-input truth assignments independently of either Shannon
// expansion or implication propagation. Duplicate input nodes share ordinals.
uint64_t truthTable(const BooleanCircuit &circuit, ID root) {
  const auto &nodes = circuit.getNodes();
  std::vector<uint64_t> values(nodes.size());
  auto value = [&](ID id) {
    return values[id / 2] ^ ((id & 1) ? UINT64_MAX : 0);
  };
  for (size_t index = 1; index != nodes.size(); ++index) {
    const auto &node = nodes[index];
    if (node.opcode == PlanOpcode::RandomBit) {
      for (unsigned assignment = 0; assignment != 64; ++assignment)
        if ((assignment >> node.b) & 1)
          values[index] |= uint64_t{1} << assignment;
    } else
      values[index] = value(node.a) & value(node.b);
  }
  return value(root);
}

unsigned lexicographicValue(unsigned rank) {
  unsigned value = 0;
  for (unsigned bit = 0; bit != 6; ++bit)
    value |= ((rank >> (5 - bit)) & 1) << bit;
  return value;
}

TEST_F(RandModelCountTest, CofactorsPreserveTruthAndSkipFalseSiblings) {
  std::vector<ID> inputs;
  for (unsigned index = 0; index != 6; ++index)
    inputs.push_back(bit(index));
  uint32_t state = 7;
  auto next = [&] { return state = state * 1664525u + 1013904223u; };
  std::vector<ID> expressions = inputs;
  for (unsigned index = 0; index != 64; ++index) {
    ID a = expressions[next() % expressions.size()] ^ (next() & 1);
    ID b = expressions[next() % expressions.size()] ^ (next() & 1);
    expressions.push_back(index % 3 == 0 ? context.conjunction(a, b)
                          : index % 3 == 1
                              ? context.exclusiveOr(a, b)
                              : context.conditional(inputs[index % 6], a, b));
  }
  for (ID expression :
       std::vector<ID>(expressions.end() - 12, expressions.end()))
    for (bool negate : {false, true}) {
      ID root = expression ^ ID(negate);
      uint64_t original = truthTable(context, root);
      for (unsigned variable = 0; variable != 7; ++variable)
        for (bool high : {false, true}) {
          uint64_t expected = 0;
          for (unsigned assignment = 0; assignment != 64; ++assignment) {
            unsigned fixed = variable == 6 ? assignment
                                           : (assignment & ~(1u << variable)) |
                                                 (unsigned(high) << variable);
            expected |= ((original >> fixed) & 1) << assignment;
          }
          EXPECT_EQ(truthTable(context, context.cofactor(root, variable, high)),
                    expected);
        }
    }

  BooleanCircuit large;
  ID guard = large.input(PlanOpcode::RandomBit, 0, 0), parity = guard;
  for (unsigned index = 1; index != 2048; ++index)
    parity = large.exclusiveOr(
        parity, large.input(PlanOpcode::RandomBit, index, index));
  ID guarded = large.conjunction(guard, parity);
  size_t before = large.getNodes().size();
  EXPECT_EQ(large.cofactor(guarded, 0, false), 0u);
  EXPECT_EQ(large.cofactor(guarded ^ 1, 0, false), 1u);
  EXPECT_EQ(large.getNodes().size(), before);
  ID late =
      large.conjunction(guard, large.input(PlanOpcode::RandomBit, 2048, 2048));
  EXPECT_EQ(large.cofactor(late, 0, false), 0u);
  ID second = large.conjunction(parity, late);
  before = large.getNodes().size();
  EXPECT_EQ(large.cofactor(second, 0, false), 0u);
  EXPECT_EQ(large.getNodes().size(), before);
}

TEST_F(RandModelCountTest, PropagatedFrontiersMatchCountsRanksAndProjections) {
  std::vector<ID> inputs;
  for (unsigned index = 0; index != 6; ++index)
    inputs.push_back(bit(index));
  std::vector<ID> expressions = inputs;
  uint32_t state = 11;
  auto next = [&] { return state = state * 1664525u + 1013904223u; };
  for (unsigned index = 0; index != 72; ++index) {
    ID a = expressions[next() % expressions.size()] ^ (next() & 1);
    ID b = expressions[next() % expressions.size()] ^ (next() & 1);
    expressions.push_back(index % 3 == 0 ? context.conjunction(a, b)
                          : index % 3 == 1
                              ? context.exclusiveOr(a, b)
                              : context.conditional(inputs[index % 6], a, b));
    if (index % 8 == 0)
      expressions.push_back(context.input(PlanOpcode::RandomBit, 0, index % 6));
  }
  for (unsigned test = 0; test != 16; ++test) {
    ID root = expressions[expressions.size() - 1 - test] ^ ID(test & 1);
    if (test & 2)
      root = context.conjunction(inputs[0], root);
    uint64_t expected = truthTable(context, root);
    ModelCounter full(context, inputs);
    ASSERT_TRUE(full.build(root));
    std::vector<unsigned> choices;
    for (unsigned rank = 0; rank != 64; ++rank) {
      unsigned value = lexicographicValue(rank);
      if ((expected >> value) & 1)
        choices.push_back(value);
    }
    ASSERT_EQ(full.count().compare(ModelCount(choices.size())), 0);
    for (unsigned rank = 0; rank != choices.size(); ++rank) {
      auto bits = full.assignment(ModelCount(rank));
      unsigned value = 0;
      for (unsigned bit = 0; bit != 6; ++bit)
        value |= unsigned(bits[bit]) << bit;
      EXPECT_EQ(value, choices[rank]);
    }
    for (unsigned mask : {0u, 0x15u, 0x2au, 0x3fu}) {
      std::vector<bool> keep(6);
      for (unsigned bit = 0; bit != 6; ++bit)
        keep[bit] = (mask >> bit) & 1;
      ModelCounter projected(context, inputs);
      ASSERT_TRUE(projected.buildProjection(root, keep));
      std::set<unsigned> values;
      for (unsigned value : choices)
        values.insert(value & mask);
      EXPECT_EQ(projected.count().compare(ModelCount(values.size())), 0);
      unsigned rank = 0;
      for (unsigned lexical = 0; lexical != 64; ++lexical) {
        unsigned value = lexicographicValue(lexical);
        if (!values.count(value))
          continue;
        auto bits = projected.assignment(ModelCount(rank++));
        unsigned actual = 0;
        for (unsigned bit = 0; bit != 6; ++bit)
          actual |= unsigned(bits[bit]) << bit;
        EXPECT_EQ(actual, value);
      }
    }
  }
}

TEST_F(RandModelCountTest, WideFrontierObligationsRetainFreeChoices) {
  std::vector<ID> inputs;
  for (unsigned index = 0; index != 135; ++index)
    inputs.push_back(bit(index));
  ID p = context.disjunction(inputs[1], inputs[2]);
  ID q = context.disjunction(inputs[3], inputs[4]);
  ID predicate = context.conjunction(
      inputs[0], context.conjunction(p, context.conditional(p, q, inputs[5])));
  ModelCount expected = ModelCount(9).shifted(130);
  ModelCounter full(context, inputs);
  ASSERT_TRUE(full.build(predicate));
  EXPECT_EQ(full.count().compare(expected), 0);
  auto first = full.assignment(ModelCount());
  EXPECT_TRUE(first[0]);
  EXPECT_FALSE(first[1]);
  EXPECT_TRUE(first[2]);
  EXPECT_FALSE(first[3]);
  EXPECT_TRUE(first[4]);
  EXPECT_EQ(std::count(first.begin() + 5, first.end(), true), 0);
  expected.subtract(ModelCount(1));
  auto last = full.assignment(expected);
  EXPECT_EQ(std::count(last.begin(), last.end(), true), 135);

  std::vector<bool> values(135), fixed(135);
  fixed[1] = fixed[130] = true;
  values[130] = true;
  full.restrict(values, fixed);
  EXPECT_EQ(full.count().compare(ModelCount(3).shifted(129)), 0);
  std::vector<bool> keep(135);
  for (unsigned bit : {0u, 1u, 3u, 5u, 129u, 130u})
    keep[bit] = true;
  ModelCounter projected(context, inputs);
  ASSERT_TRUE(projected.buildProjection(predicate, keep));
  EXPECT_EQ(projected.count().compare(ModelCount(32)), 0);

  // The repeated guard prevents decision() from peeling it off before fact
  // propagation. Its false AND forces the distant input without fixing any
  // of the 133 free inputs or changing their lexicographic order.
  ID sharedGuard = context.conjunction(
      inputs[0], context.conjunction(inputs[0], inputs[130]) ^ 1);
  ModelCounter shared(context, inputs);
  ASSERT_TRUE(shared.build(sharedGuard));
  EXPECT_EQ(shared.count().compare(ModelCount::powerOfTwo(133)), 0);
  first = shared.assignment(ModelCount());
  EXPECT_TRUE(first[0]);
  EXPECT_EQ(std::count(first.begin(), first.end(), true), 1);
  ModelCount finalRank = ModelCount::powerOfTwo(133);
  finalRank.subtract(ModelCount(1));
  last = shared.assignment(finalRank);
  EXPECT_FALSE(last[130]);
  EXPECT_EQ(std::count(last.begin(), last.end(), true), 134);
}

TEST_F(RandModelCountTest, FrontierValidationAndBudgetedPreparation) {
  std::vector<ID> inputs;
  for (unsigned index = 0; index != 6; ++index)
    inputs.push_back(bit(index));
  ID p = context.disjunction(inputs[1], inputs[2]);
  ID q = context.disjunction(inputs[3], inputs[4]);
  ID predicate = context.conjunction(
      inputs[0], context.conjunction(context.disjunction(inputs[0] ^ 1, p), q));
  bool incomplete = false, complete = false;
  for (size_t budget : {1u, 4u, 16u, 64u, 10000u}) {
    BooleanCircuit copy = context;
    ModelCounter prepared(copy, inputs);
    if (!prepared.prepareDiagram(predicate, budget, 10000)) {
      incomplete = true;
      ModelCounter fallback(copy, inputs);
      ASSERT_TRUE(fallback.build(predicate));
      EXPECT_EQ(fallback.count().compare(ModelCount(18)), 0);
      continue;
    }
    complete = true;
    BooleanCircuit exported;
    std::vector<ID> renamed;
    for (unsigned bit = 0; bit != 6; ++bit)
      renamed.push_back(exported.input(PlanOpcode::RandomBit, bit, bit));
    ID root = prepared.exportDiagram(exported, renamed);
    EXPECT_EQ(truthTable(exported, root), truthTable(context, predicate));
  }
  EXPECT_TRUE(incomplete);
  EXPECT_TRUE(complete);

  for (bool forced : {false, true}) {
    BooleanCircuit invalid;
    ID a = invalid.input(PlanOpcode::RandomBit, 0, 0);
    ID b = invalid.input(PlanOpcode::RandomBit, 1, 1);
    ID bad = invalid.input(PlanOpcode::RandomBit, 2, 2);
    ID root =
        invalid.conjunction(a, forced ? bad : invalid.disjunction(b, bad));
    ModelCounter counter(invalid, {a, b});
    EXPECT_FALSE(counter.build(root));
  }
  BooleanCircuit unsupported;
  ID a = unsupported.input(PlanOpcode::RandomBit, 0, 0);
  ID b = unsupported.input(PlanOpcode::RandomBit, 1, 1);
  ID parameter = unsupported.input(PlanOpcode::CaptureBit, 0);
  ModelCounter counter(unsupported, {a, b});
  EXPECT_FALSE(counter.build(unsupported.conjunction(
      unsupported.conjunction(a, parameter), unsupported.disjunction(a, b))));
}

TEST(RandomFlatMapTest, FindsEveryEntryAcrossGrowth) {
  talos::random::FlatMap<uint64_t, uint32_t> map;
  for (uint32_t key = 0; key != 5000; ++key)
    ASSERT_TRUE(map.insert(uint64_t(key) * 7919, key).second);
  for (uint32_t key = 0; key != 5000; ++key) {
    const uint32_t *value = map.find(uint64_t(key) * 7919);
    ASSERT_NE(value, nullptr);
    EXPECT_EQ(*value, key);
    auto [existing, inserted] = map.insert(uint64_t(key) * 7919, 0);
    EXPECT_FALSE(inserted);
    EXPECT_EQ(*existing, key);
  }
  EXPECT_FALSE(map.contains(1));
}

} // namespace
