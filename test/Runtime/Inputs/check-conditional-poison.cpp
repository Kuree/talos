#include <cassert>
#include <cstdint>
#include <cstring>
#include <initializer_list>

extern "C" {
extern uint8_t __talos_state_value[];
extern uint8_t __talos_state_unknown[];
extern uint8_t __talos_eval_step_four_state_fallback_v1;
uint32_t __talos_eval_kernel_conditional_ready_0_v1_i32();
void __talos_eval_promotion_invalidate_v1();
int __talos_eval_four_state_nba_handoff_v1(void *, void *, void *);
}
#define TALOS_TEST_STRINGIFY_(text) #text
#define TALOS_TEST_STRINGIFY(text) TALOS_TEST_STRINGIFY_(text)
extern "C" int executeSelectedLane(void *) asm(TALOS_TEST_STRINGIFY(
    __USER_LABEL_PREFIX__) "__talos_direct_fragment_2_5.__talos_execute");

int main() {
  auto *values = __talos_state_value;
  auto *unknown = __talos_state_unknown;
  // The outer source branch rejects each of these inputs. Its flagged
  // inner truncation must not poison the optional entry proof (LRM 12.4).
  for (unsigned input : {8u, 16u, 127u, 255u})
    for (unsigned payload : {0u, 255u}) {
      std::memset(values, 0, 5);
      std::memset(unknown, 0, 5);
      values[1] = input;
      values[2] = payload;
      unknown[2] = 255;
      values[3] = 0x55;
      values[4] = 37;
      __talos_eval_promotion_invalidate_v1();
      assert(__talos_eval_kernel_conditional_ready_0_v1_i32());
      __talos_eval_step_four_state_fallback_v1 = 0;
      assert(executeSelectedLane(nullptr) == 0);
      assert(!__talos_eval_step_four_state_fallback_v1);
      assert(values[4] == 38 && unknown[4] == 0);
      assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr,
                                                 nullptr) == 0);
      assert(values[3] == 0x55 && unknown[3] == 0);
      assert(values[2] == payload && unknown[2] == 255);
    }
  // A valid taken truncation still observes the unknown payload and stages
  // its X arithmetic result for later NBA publication (LRM 10.4.2).
  values[1] = 1;
  assert(!__talos_eval_kernel_conditional_ready_0_v1_i32());
  __talos_eval_step_four_state_fallback_v1 = 0;
  assert(executeSelectedLane(nullptr) == 0);
  assert(__talos_eval_step_four_state_fallback_v1);
  assert(values[4] == 39 && unknown[4] == 0);
  assert(values[3] == 0x55 && unknown[3] == 0);
  assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr, nullptr) == 0);
  assert(values[3] == 0 && unknown[3] == 255);
}
