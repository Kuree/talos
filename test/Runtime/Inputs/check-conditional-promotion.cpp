#include "talos/Runtime/Runtime.h"

#include <cassert>
#include <cstdint>
#include <cstring>
#include <initializer_list>

extern "C" {
extern uint8_t __talos_state_value[];
extern uint8_t __talos_state_unknown[];
extern uint8_t __talos_eval_kernel_promotion_latched_v1[];
extern uint8_t __talos_eval_step_four_state_fallback_v1;
bool __talos_eval_kernel_conditional_ready_0_v1();
bool __talos_eval_kernel_promotion_ready_v1(uint64_t);
void __talos_eval_promotion_invalidate_range_v1(uint64_t, uint64_t);
void __talos_eval_promotion_invalidate_v1();
void __talos_eval_promotion_recheck_range_v1(uint64_t, uint64_t);
int __talos_eval_four_state_nba_handoff_v1(void *, void *, void *);
}

#define TALOS_TEST_STRINGIFY_(text) #text
#define TALOS_TEST_STRINGIFY(text) TALOS_TEST_STRINGIFY_(text)
extern "C" int executeSelectedLane(void *) asm(TALOS_TEST_STRINGIFY(
    __USER_LABEL_PREFIX__) "__talos_direct_fragment_2_5.__talos_execute");

#ifndef CONDITIONAL_JOIN
#define CONDITIONAL_JOIN 0
#endif
#ifndef FOUR_STATE_ENABLE
#define FOUR_STATE_ENABLE 0
#endif

int main() {
  constexpr unsigned bytes = CONDITIONAL_JOIN ? 6 : 5;
  constexpr unsigned enable = CONDITIONAL_JOIN ? 5 : 1;
  auto *values = __talos_state_value;
  auto *unknown = __talos_state_unknown;
  std::memset(values, 0, bytes);
  std::memset(unknown, 0, bytes);
  unknown[2] = 0xff; // uninitialized payload
  unknown[3] = 0xff; // write-only NBA destination is no activation input
  __talos_eval_promotion_invalidate_range_v1(0, 40);
  auto check = [&](bool expected) {
    uint8_t oldValues[bytes], oldUnknown[bytes];
    std::memcpy(oldValues, values, bytes);
    std::memcpy(oldUnknown, unknown, bytes);
    for (unsigned repeat = 0; repeat != 4; ++repeat)
      assert(__talos_eval_kernel_conditional_ready_0_v1() == expected);
    assert(std::memcmp(oldValues, values, bytes) == 0);
    assert(std::memcmp(oldUnknown, unknown, bytes) == 0);
    if (unknown[2]) {
      // A true per-activation result must not become a cached whole-state
      // proof. A value-only enable update can make this payload relevant.
      assert(__talos_eval_kernel_promotion_latched_v1[0] !=
             TALOS_RT_PROMOTION_LATCH_KNOWN);
      assert(!__talos_eval_kernel_promotion_ready_v1(0));
    }
  };
  check(true);
  values[enable] = 1; // no unknown-plane transition or invalidation
  check(false);
  values[enable] = 0;
  check(true);
  unknown[4] = 0xff; // unconditional counter remains part of the proof
  __talos_eval_promotion_invalidate_range_v1(32, 8);
  check(false);
  unknown[4] = 0;
  __talos_eval_promotion_recheck_range_v1(32, 8);
  check(true);
  // Exact X and exact Z are both retained; neither is silently converted
  // into a two-state value when the corresponding access actually executes.
  for (uint8_t payload : {uint8_t{0}, uint8_t{255}}) {
    values[2] = payload;
    values[enable] = 1;
    check(false);
    values[enable] = 0;
    check(true);
  }
  unknown[2] = 0;
  __talos_eval_promotion_recheck_range_v1(16, 8);
  values[enable] = 1;
  check(true);
  assert(__talos_eval_kernel_promotion_latched_v1[0] ==
         TALOS_RT_PROMOTION_LATCH_KNOWN);
  unknown[2] = 0xff;
  __talos_eval_promotion_invalidate_range_v1(16, 8);
  check(false);
  values[enable] = 0;
  check(true);
  // Context reuse may retain a negative scan hint, but clears positives.
  unknown[4] = 0xff;
  __talos_eval_promotion_invalidate_v1();
  check(false);

  // Use the real generated selector, not a test-side branch over the proof.
  // The counter store executes exactly once in either selected domain.
  unknown[4] = 0;
  __talos_eval_promotion_recheck_range_v1(32, 8);
  auto execute = [&](bool fallback) {
    uint8_t oldCounter = values[4];
    __talos_eval_step_four_state_fallback_v1 = 0;
    assert(executeSelectedLane(nullptr) == 0);
    assert(values[4] == uint8_t(oldCounter + 1) && unknown[4] == 0);
    assert(bool(__talos_eval_step_four_state_fallback_v1) == fallback);
  };
  values[3] = 0x55;
  unknown[3] = 0;
  __talos_eval_promotion_invalidate_range_v1(24, 8);
  values[enable] = 0;
  execute(false);
  assert(values[3] == 0x55 && unknown[3] == 0);
  assert(unknown[2] == 0xff); // no payload access or NBA staging on this path

  values[enable] = 1;
  values[2] = 0;
  execute(true);
  assert(values[3] == 0x55 && unknown[3] == 0); // deferred update
  unknown[2] = 0;
  values[2] = 41;
  __talos_eval_promotion_recheck_range_v1(16, 8);
  assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr, nullptr) ==
         0);
  assert(values[3] == 0 && unknown[3] == 0xff); // captured X RHS

  execute(false);
  values[2] = 7; // value-only change after staging must not change the NBA RHS
  assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr, nullptr) ==
         0);
  assert(values[3] == 42 && unknown[3] == 0);

  values[2] = 0xff;
  unknown[2] = 0xff; // exact Z remains Z in source state
  __talos_eval_promotion_invalidate_range_v1(16, 8);
  execute(true);
  assert(values[2] == 0xff && unknown[2] == 0xff);
  assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr, nullptr) ==
         0);
  assert(values[3] == 0 && unknown[3] == 0xff); // Z + 1 is X (LRM 11.4.3)
  if (CONDITIONAL_JOIN) {
    // Every predecessor matters: with A=false, B=true must still reject the
    // unused-payload proof. Execute the real selector for all four choices.
    for (unsigned a : {0u, 1u})
      for (unsigned b : {0u, 1u}) {
        values[1] = a;
        values[enable] = b;
        values[3] = 0x7b;
        unknown[3] = 0;
        __talos_eval_promotion_invalidate_range_v1(24, 8);
        check(!b);
        execute(bool(b));
        assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr,
                                                      nullptr) == 0);
        assert(values[3] == (b ? 0 : 0x7b));
        assert(unknown[3] == (b ? 0xff : 0));
      }
  }
  if (FOUR_STATE_ENABLE) {
    // LRM12.4: both X and Z are false as a one-bit if condition. The full
    // proof still rejects the unknown control; canonical execution must
    // leave the payload unobserved and stage no NBA on that path.
    for (unsigned control : {0u, 1u}) {
      values[enable] = control;
      unknown[enable] = 1;
      __talos_eval_promotion_invalidate_range_v1(8, 1);
      values[3] = 0x7b;
      unknown[3] = 0;
      __talos_eval_promotion_invalidate_range_v1(24, 8);
      check(false);
      execute(true);
      assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr,
                                                    nullptr) == 0);
      assert(values[3] == 0x7b && unknown[3] == 0);
      assert(unknown[2] == 0xff && values[2] == 0xff);
    }
  }
}
