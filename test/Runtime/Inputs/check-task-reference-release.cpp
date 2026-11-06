#include "talos/Runtime/Runtime.h"

#include <cstdio>
#include <cstdlib>

static uint64_t reference = UINT64_MAX;
static unsigned allocations;

extern "C" talos_rt_status __real_talos_rt_v1_native_state_alloc(
    talos_rt_context *, uint64_t, const uint8_t *, const uint8_t *, uint64_t *);

extern "C" talos_rt_status
__wrap_talos_rt_v1_native_state_alloc(talos_rt_context *context, uint64_t width,
                                      const uint8_t *value,
                                      const uint8_t *unknown, uint64_t *out) {
  auto status = __real_talos_rt_v1_native_state_alloc(context, width, value,
                                                      unknown, out);
  if (status == TALOS_RT_OK && width == 9) {
    reference = *out;
    ++allocations;
  }
  return status;
}

extern "C" void __real_talos_rt_v1_context_destroy(talos_rt_context *);

extern "C" void __wrap_talos_rt_v1_context_destroy(talos_rt_context *context) {
  uint8_t dummy = 0;
  uint16_t value = 0;
  if (allocations != 1 ||
      talos_rt_v1_native_state_load_plane(
          context, &dummy, 0, reference, 9, 0, 0,
          reinterpret_cast<uint8_t *>(&value)) != TALOS_RT_INVALID_HANDLE) {
    std::fputs("automatic task reference still live or not allocated\n",
               stderr);
    std::abort();
  }
  std::puts("automatic task reference released");
  __real_talos_rt_v1_context_destroy(context);
}
