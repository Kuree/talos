//===- SAIFTest.cpp - Activity collection at canonical publication --------===//

#include "../lib/RuntimeInternal.h"
#include "../lib/SAIFInternal.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"
#include "gtest/gtest.h"
#include <fstream>
#include <iterator>

namespace {
class SAIFTest : public testing::Test {
protected:
  void SetUp() override {
    execution.version = TALOS_RT_VERSION;
    execution.state_bit_count = 128;
    ASSERT_EQ(talos_rt_v1_context_create_for_design(&execution, &context),
              TALOS_RT_OK);
    ASSERT_EQ(talos_rt_v1_native_state_register_static(context, 1, 0, 128),
              TALOS_RT_OK);
    handle = talos_rt_v1_native_state_static_handle(1);
    output = testing::TempDir() + "talos-saif-" +
             testing::UnitTest::GetInstance()->current_test_info()->name() +
             ".saif";
  }
  void TearDown() override {
    talos_rt_v1_context_destroy(context);
    std::remove(output.c_str());
  }
  std::string read() {
    std::ifstream file(output);
    return {std::istreambuf_iterator<char>(file),
            std::istreambuf_iterator<char>()};
  }
  void transition(uint64_t time, uint8_t oldValue, uint8_t oldUnknown,
                  uint8_t value, uint8_t unknown) {
    context->schedulerTime = time;
    talos_rt_v1_scheduler_signal_transition(context, handle, 1, &oldValue,
                                            &oldUnknown, &value, &unknown);
  }
  talos_rt_context *context = nullptr;
  talos_rt_execution_descriptor_v1 execution{};
  uint64_t handle = 0;
  std::string output;
};

TEST_F(SAIFTest, CountsKnownEdgesAndAllFourResidenceStatesForAliases) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1000000),
            TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context, handle, "top\0gate", 9, "Q", 1,
                                  "sequential", 0),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  transition(2, 0, 0, 1, 0);
  transition(2, 1, 0, 0, 0);
  transition(2, 0, 0, 1, 0);
  transition(5, 1, 0, 0, 1);
  transition(7, 0, 1, 1, 1);
  transition(10, 1, 1, 0, 0);
  context->schedulerTime = 12;
  ASSERT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OK);
  std::string text = read();
  EXPECT_NE(
      text.find(
          "(q (T0 4000000) (T1 3000000) (TX 2000000) (TZ 3000000) (TC 3))"),
      std::string::npos);
  EXPECT_NE(
      text.find(
          "(Q (T0 4000000) (T1 3000000) (TX 2000000) (TZ 3000000) (TC 3))"),
      std::string::npos);
  EXPECT_NE(text.find("(VIRTUAL_INSTANCE \"sequential\" gate"),
            std::string::npos);
  EXPECT_EQ(text.find("(TG"), std::string::npos);
  EXPECT_EQ(text.find("(TB"), std::string::npos);
}

TEST_F(SAIFTest, PartialRangeDoesNotTouchUnchangedWatchedBits) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context,
                                  talos_rt_stable_handle_offset(handle, 63),
                                  "top", 4, "q[63]", 0, nullptr, 0),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context,
                                  talos_rt_stable_handle_offset(handle, 64),
                                  "top", 4, "q[64]", 0, nullptr, 0),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  context->schedulerTime = 3;
  uint8_t zero = 0, one = 1;
  talos_rt_v1_scheduler_signal_transition(
      context, talos_rt_stable_handle_offset(handle, 63), 2, &zero, nullptr,
      &one, nullptr);
  context->schedulerTime = 5;
  ASSERT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OK);
  std::string text = read();
  EXPECT_NE(text.find("(q[63] (T0 3) (T1 2) (TX 0) (TZ 0) (TC 1))"),
            std::string::npos);
  EXPECT_NE(text.find("(q[64] (T0 5) (T1 0) (TX 0) (TZ 0) (TC 0))"),
            std::string::npos);
}

TEST_F(SAIFTest, ExactFemtosecondsBeyond64Bits) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), UINT64_MAX),
            TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  context->schedulerTime = UINT64_MAX;
  ASSERT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OK);
  std::string text = read();
  EXPECT_NE(text.find("(DURATION 340282366920938463426481119284349108225)"),
            std::string::npos);
  EXPECT_NE(text.find("(T0 340282366920938463426481119284349108225)"),
            std::string::npos);
}

TEST_F(SAIFTest, RejectsInvalidBindingsAndDuplicateOutputs) {
  EXPECT_EQ(talos_rt_v1_saif_configure(nullptr, output.c_str(), 1),
            TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(talos_rt_v1_saif_configure(context, "", 1),
            TALOS_RT_INVALID_ARGUMENT);
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, UINT64_MAX, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_INVALID_HANDLE);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 3, "q", 0, nullptr, 0),
      TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q)", 0, nullptr, 0),
      TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "\\q", 0, nullptr, 0),
      TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q[01]", 0, nullptr, 0),
      TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "t\\op", 5, "q", 0, nullptr, 0),
      TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 1,
                                  "invalid\"type", 0),
            TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 1,
                                  "invalid\ntype", 0),
            TALOS_RT_INVALID_ARGUMENT);
  EXPECT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 4),
      TALOS_RT_INVALID_ARGUMENT);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_OK);
  EXPECT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_INVALID_ARGUMENT);
}

TEST_F(SAIFTest, EncodedNameAndPathLimitsMatchDecodedIRLimits) {
  std::string name;
  for (unsigned i = 0; i < 16384; ++i)
    name += "\\$";
  std::string instance;
  for (unsigned i = 0; i < 128; ++i) {
    instance += name;
    instance += '\0';
  }
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context, handle, instance.data(),
                                  instance.size(), name.c_str(), 0, nullptr, 0),
            TALOS_RT_OK);
  name += "\\$";
  EXPECT_EQ(talos_rt_v1_saif_bind(context, handle, "top", 4, name.c_str(), 0,
                                  nullptr, 0),
            TALOS_RT_INVALID_ARGUMENT);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
}

TEST_F(SAIFTest, OutputIOFailureIsReported) {
  std::string invalid = output + "/missing/out.saif";
  ASSERT_EQ(talos_rt_v1_saif_configure(context, invalid.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "q", 0, nullptr, 0),
      TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  EXPECT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_IO_ERROR);
}

TEST_F(SAIFTest, EmptyVirtualCellTypeRemainsAQuotedString) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context, handle, "top\0v", 6, "A", 1, "", 0),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OK);
  EXPECT_NE(read().find("(VIRTUAL_INSTANCE \"\" v"), std::string::npos);
}

TEST_F(SAIFTest, CellPlanRejectsMalformedAndIllegalCharacterization) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "A", 1, nullptr, 0),
      TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_bind(context,
                                  talos_rt_stable_handle_offset(handle, 1),
                                  "top", 4, "Y", 1, nullptr, 0),
            TALOS_RT_OK);
  // Two pins, one conditional output group, one !A rule with an A path.
  std::vector<uint64_t> valid{1, 2, 1, 0, 0, 1, 1, 1, 2, 1,
                              1, 2, 1, 0, 0, 1, 0, 0, 1, 0};
  auto configure = [&](const std::vector<uint64_t> &plan) {
    return talos_rt_v1_saif_cell(context, "top", 4, "cell", plan.data(),
                                 plan.size());
  };
  for (size_t size = 0; size < valid.size(); ++size) {
    auto truncated = valid;
    truncated.resize(size);
    EXPECT_EQ(configure(truncated), TALOS_RT_INVALID_ARGUMENT) << size;
  }
  for (auto mutation : {std::pair<size_t, uint64_t>{0, 2},
                        {3, 2},
                        {4, 1},
                        {6, 0},
                        {7, 0},
                        {8, 0},
                        {11, 4097},
                        {13, 5},
                        {14, 2},
                        {19, 1}}) {
    auto plan = valid;
    plan[mutation.first] = mutation.second;
    EXPECT_EQ(configure(plan), TALOS_RT_INVALID_ARGUMENT) << mutation.first;
  }
  EXPECT_EQ(configure({1, 2, 1, 0, 0, 1, 1, 1, 2, 1, 0, 0, 0}),
            TALOS_RT_INVALID_ARGUMENT); // Only COND_DEFAULT.
  EXPECT_EQ(configure({1, 2, 1, 0, 0, 1, 1, 1, 0, 1, 0, 0, 1, 1, 0}),
            TALOS_RT_INVALID_ARGUMENT); // Only IOPATH_DEFAULT.
  EXPECT_EQ(configure({1, 2, 1, 0, 0, 1, 1, UINT64_MAX, 1, 1, 0, 0, 0}),
            TALOS_RT_INVALID_ARGUMENT); // Leakage without conditions.
  ASSERT_EQ(configure(valid), TALOS_RT_OK);
  EXPECT_EQ(configure(valid), TALOS_RT_INVALID_ARGUMENT);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  EXPECT_EQ(configure(valid), TALOS_RT_INVALID_ARGUMENT);
}

TEST_F(SAIFTest, ReferenceFailureAtFinishIsReported) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  talos_rt_context *reference = nullptr;
  ASSERT_EQ(talos_rt_v1_context_create(&reference), TALOS_RT_OK);
  context->saif->referenceContext = {reference, talos_rt_v1_context_destroy};
  context->saif->referenceStarted = true;
  reference->saifReferenceModel = true;
  reference->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
  EXPECT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OUT_OF_RESOURCES);
}

TEST_F(SAIFTest, MixedTGEstimateConservesStateAndPolarityBudgets) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  ASSERT_EQ(
      talos_rt_v1_saif_bind(context, handle, "top", 4, "A", 1, nullptr, 0),
      TALOS_RT_OK);
  auto b = talos_rt_stable_handle_offset(handle, 1);
  ASSERT_EQ(talos_rt_v1_saif_bind(context, b, "top", 4, "B", 1, nullptr, 0),
            TALOS_RT_OK);
  // A is output; split its activity into B and default state buckets.
  const uint64_t plan[] = {1, 2, 1, 0, 1, 1, 0, 0, 2,
                           2, 1, 1, 0, 0, 1, 1, 0, 0};
  ASSERT_EQ(talos_rt_v1_saif_cell(context, "top", 4, "cell", plan,
                                  sizeof(plan) / sizeof(plan[0])),
            TALOS_RT_OK);
  ASSERT_EQ(talos_rt_v1_saif_seal(context), TALOS_RT_OK);
  transition(1, 0, 0, 1, 0);
  transition(2, 1, 0, 0, 0);
  context->schedulerTime = 3;
  uint8_t zero = 0, one = 1;
  talos_rt_v1_scheduler_signal_transition(context, b, 1, &zero, nullptr, &one,
                                          nullptr);
  ASSERT_EQ(context->schedulerStatus, TALOS_RT_OK);
  transition(3, 0, 0, 1, 0);
  transition(4, 1, 0, 0, 0);
  transition(5, 0, 0, 1, 0);
  // Supply an independently measured reference tally: two rising and one
  // falling functional edge versus three rising and two falling physical edges.
  auto &point = context->saif->observations[0];
  point.referenceComparable = true;
  point.referenceEdges[1] = 2;
  point.referenceEdges[0] = 1;
  context->schedulerTime = 6;
  ASSERT_EQ(talos_rt_v1_saif_finish(context), TALOS_RT_OK);
  EXPECT_EQ(point.toggles, 5u);
  EXPECT_EQ(point.extra.tg, 2u);
  auto &rules = context->saif->cells[0].groups[0].rules;
  ASSERT_EQ(rules.size(), 2u);
  EXPECT_EQ(rules[0].counts[0].tc, 2u);
  EXPECT_EQ(rules[0].counts[1].tc, 1u);
  EXPECT_EQ(rules[1].counts[0].tc, 1u);
  EXPECT_EQ(rules[1].counts[1].tc, 1u);
  EXPECT_EQ(rules[0].counts[0].tg + rules[1].counts[0].tg, 1u);
  EXPECT_EQ(rules[0].counts[1].tg + rules[1].counts[1].tg, 1u);
  for (const auto &rule : rules)
    for (const auto &counts : rule.counts)
      EXPECT_LE(counts.tg, counts.tc);
}

TEST_F(SAIFTest, CausalStateSurvivesDelayAndRetiresAtTheNextWaitOrTermination) {
  ASSERT_EQ(talos_rt_v1_saif_configure(context, output.c_str(), 1),
            TALOS_RT_OK);
  for (uint64_t logical = 1; logical <= 1000; ++logical) {
    context->saif->wakeups[logical] = std::make_shared<SAIFCause>();
    talos_rt_fragment_action_v1 action{};
    action.kind = TALOS_RT_FRAGMENT_SUSPEND;
    action.suspend_kind = TALOS_RT_SUSPEND_DELAY;
    {
      SAIFExecutionScope activity(context, logical, &action);
      EXPECT_EQ(context->saif->resumptions.size(), 1u);
    }
    EXPECT_EQ(context->saif->resumptions.size(), 1u);
    action.kind =
        logical % 2 ? TALOS_RT_FRAGMENT_TERMINATE : TALOS_RT_FRAGMENT_SUSPEND;
    action.suspend_kind = TALOS_RT_SUSPEND_CHANGE;
    {
      SAIFExecutionScope activity(context, logical, &action);
    }
    EXPECT_TRUE(context->saif->resumptions.empty());
    EXPECT_TRUE(context->saif->wakeups.empty());
  }
}
} // namespace
