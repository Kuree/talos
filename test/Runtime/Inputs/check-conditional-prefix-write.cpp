#include <cassert>
#include <cstdint>
#include <cstring>
#include <initializer_list>

extern "C" {
extern uint8_t __talos_state_value[];
extern uint8_t __talos_state_unknown[];
extern uint8_t __talos_eval_step_four_state_fallback_v1;
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
  for (unsigned write : {0u, 1u})
    for (unsigned initial : {0u, 1u})
      for (unsigned payload : {0u, 255u}) {
        std::memset(values, 0, 6);
        std::memset(unknown, 0, 6);
        values[1] = write;
        values[5] = initial;
        values[2] = payload;
        unknown[2] = 255;
        values[3] = 0x55;
        values[4] = 37;
        __talos_eval_promotion_invalidate_v1();
        __talos_eval_step_four_state_fallback_v1 = 0;
        assert(executeSelectedLane(nullptr) == 0);
        bool enabled = write || initial;
        assert(values[5] == unsigned(enabled));
        assert(values[4] == 38 && unknown[4] == 0);   // no replayed prefix
        assert(values[3] == 0x55 && unknown[3] == 0); // NBA still pending
        if (enabled)
          assert(__talos_eval_step_four_state_fallback_v1);
        assert(__talos_eval_four_state_nba_handoff_v1(nullptr, nullptr,
                                                      nullptr) == 0);
        assert(values[3] == (enabled ? 0 : 0x55));
        assert(unknown[3] == (enabled ? 255 : 0));
        assert(values[2] == payload && unknown[2] == 255);
      }
}
