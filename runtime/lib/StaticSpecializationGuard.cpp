//===- StaticSpecializationGuard.cpp - Shared cold VPI root scans --------===//
#include "StaticSpecializationGuard.h"

extern "C" TALOS_RT_FEATURE_HELPER __attribute__((noinline)) uint32_t
talos_rt_v1_static_specialization_guard_roots(talos_rt_context *context,
                                              const uint32_t *roots,
                                              uint64_t count) {
  if (!count)
    return 1;
  if (!context || !roots)
    return 0;
  uint32_t allowed = 1;
  // LRM 38.34/10.6.2: retain each dependency's exact dirty/override query.
  // Inlining the existing scalar implementation removes repeated ABI and
  // constant-argument checks, while all diagnostic visits remain observable.
  for (uint64_t index = 0; index != count; ++index)
    allowed &= staticSpecializationRootGuard(context, UINT32_MAX, roots[index],
                                             TALOS_RT_STATIC_ROOT_READ |
                                                 TALOS_RT_STATIC_ROOT_WRITE);
  return allowed;
}
