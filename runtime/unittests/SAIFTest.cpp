//===- SAIFTest.cpp - Activity collection at canonical publication --------===//

#include "../lib/RuntimeInternal.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHandle.h"
#include "gtest/gtest.h"
#include <fstream>
#include <iterator>

namespace {
class SAIFTest : public testing::Test {
protected:
  void SetUp() override {
    talos_rt_execution_descriptor_v1 execution{};
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
} // namespace
