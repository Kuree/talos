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

extern "C" TALOS_RT_FEATURE_HELPER __attribute__((noinline)) uint32_t
talos_rt_v1_observed_writer_guard(talos_rt_context *context,
                                  const uint32_t *actors, uint64_t count) {
  if (!context || (count && !actors) || context->nativeScheduleDeoptimized ||
      !context->nativeScheduleTransientDirtyRoots.empty() ||
      !context->forceMask.empty() || !context->assignMask.empty())
    return 0;
  auto *observed = context->observedWriters.get();
  if (!observed)
    return !context->nativeScheduleDirtyRootsPresent;
  if (!context->nativeSchedulePersistentDirtyRoots.empty())
    return 0;
  // The compiler emits a sorted set of writer slots for each owner/group.
  // For a single subscribed writer compare the slot directly. A group
  // disjoint from it costs two bounds checks independent of its width.
  if (count) {
    uint32_t last = actors[count - 1];
    if (last >= observed->actorUsers.size())
      return 0;
    if (observed->activeActorCount == 1) {
      uint32_t slot = observed->activeActorXor;
      if (actors[0] <= slot && slot <= last &&
          (count == 1 || std::binary_search(actors, actors + count, slot)))
        return 0;
    } else if (observed->activeActorCount) {
      for (uint64_t i = 0; i != count; ++i)
        if (observed->actorUsers[actors[i]])
          return 0;
    }
  }
  if (context->signalDiagnosticsReport)
    ++observed->nativeOwnerChecks;
  return 1;
}

extern "C" TALOS_RT_FEATURE_HELPER uint32_t
talos_rt_v1_observed_writer_guard_cached(talos_rt_context *context,
                                         const uint32_t *actors, uint64_t count,
                                         uint64_t *cacheEntry,
                                         uint64_t *epoch) {
  uint32_t allowed = talos_rt_v1_observed_writer_guard(context, actors, count);
  if (allowed && cacheEntry && epoch && *epoch && *epoch != UINT64_MAX &&
      context->nativeScopedWrite && context->observedWriters &&
      context->execution && context->nativeSchedulePlan &&
      (context->execution->flags & TALOS_RT_EXECUTION_VPI_PUBLISHING_WRITERS) &&
      !context->vpiObservationDemand &&
      !context->nativeScheduleDirtyRootsPresent) {
    auto &observed = *context->observedWriters;
    if (observed.modelGuardEpoch != epoch) {
      observed.revokeOwnerGuard();
      observed.modelGuardEpoch = epoch;
    }
    *cacheEntry = *epoch;
  }
  return allowed;
}
