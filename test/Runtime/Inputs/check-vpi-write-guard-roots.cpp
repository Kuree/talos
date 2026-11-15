#include "talos/Runtime/Runtime.h"
#include <cassert>
#include <cstdio>

#define TALOS_TEST_STRINGIFY_(text) #text
#define TALOS_TEST_STRINGIFY(text) TALOS_TEST_STRINGIFY_(text)
#define TALOS_TEST_SYMBOL(name) TALOS_TEST_STRINGIFY(__USER_LABEL_PREFIX__) name
extern "C" uint32_t
guard(talos_rt_context *, const uint32_t *,
      uint64_t) asm(TALOS_TEST_SYMBOL("__talos_eval_write_guard_roots_v1_i32"));
extern "C" const uint32_t
    roots0[] asm(TALOS_TEST_SYMBOL("__talos_eval_write_guard_states_0_v1"));
extern "C" const uint32_t
    roots1[] asm(TALOS_TEST_SYMBOL("__talos_eval_write_guard_states_1_v1"));
extern "C" const uint32_t
    roots2[] asm(TALOS_TEST_SYMBOL("__talos_eval_write_guard_states_2_v1"));
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
  const uint32_t *roots[] = {roots0, roots1, roots2};
  for (owner = 0; owner != 3; ++owner)
    for (uint32_t result = 0; result <= 3; result += 3) {
      returned = result;
      calls = 0;
      assert(guard(context, roots[owner], 2) == (result != 0));
      assert(calls == 1);
    }
  std::puts("shared VPI guard: exact roots, boolean result");
}
