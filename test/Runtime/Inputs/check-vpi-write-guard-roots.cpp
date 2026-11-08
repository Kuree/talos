#include "talos/Runtime/Runtime.h"
#include <cassert>
#include <cstdio>
#include <initializer_list>

#define TALOS_TEST_STRINGIFY_(text) #text
#define TALOS_TEST_STRINGIFY(text) TALOS_TEST_STRINGIFY_(text)
#define TALOS_TEST_SYMBOL(name) TALOS_TEST_STRINGIFY(__USER_LABEL_PREFIX__) name
extern "C" bool guard0(talos_rt_context *) asm(
    TALOS_TEST_SYMBOL("__talos_eval_write_guard_0_v1"));
extern "C" bool guard1(talos_rt_context *) asm(
    TALOS_TEST_SYMBOL("__talos_eval_write_guard_1_v1"));
extern "C" bool guard2(talos_rt_context *) asm(
    TALOS_TEST_SYMBOL("__talos_eval_write_guard_2_v1"));
extern "C" uint32_t __talos_static_specialization_fast_v1;
static auto *const context = reinterpret_cast<talos_rt_context *>(0x1234);
static uint32_t owner, returned, calls;
extern "C" uint32_t __wrap_talos_rt_v1_static_specialization_guard_roots(
    talos_rt_context *ctx, const uint32_t *roots, uint64_t count) {
  assert(ctx == context && count == 2);
  assert(roots[0] == owner + 1 && roots[1] == owner + 2);
  ++calls;
  return returned;
}
int main() {
  bool (*guards[])(talos_rt_context *) = {guard0, guard1, guard2};
  for (owner = 0; owner != 3; ++owner)
    for (uint32_t fast : {0u, 1u})
      for (uint32_t result : {0u, 3u}) {
        __talos_static_specialization_fast_v1 = fast;
        returned = result;
        calls = 0;
        assert(guards[owner](context) == (fast || result != 0));
        assert(calls == (fast ? 0u : 1u));
      }
  std::puts("shared VPI guard: exact roots, clean fast path, boolean result");
}
