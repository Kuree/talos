//===- StaticSpecializationGuard.h - Private writable VPI guards -*- C++
//-*-===//
#ifndef TALOS_RUNTIME_LIB_STATICSPECIALIZATIONGUARD_H
#define TALOS_RUNTIME_LIB_STATICSPECIALIZATIONGUARD_H

#include "PrivateEntries.h"
#include "ProcessShared.h"

// Keep the scalar ABI and batch query on one implementation. The compiler
// supplies actor UINT32_MAX and read/write flags for each immutable owner root.
inline __attribute__((always_inline)) uint32_t
staticSpecializationRootGuard(talos_rt_context *context, uint32_t actorSlot,
                              uint32_t staticState, uint32_t flags) {
  if (!context ||
      (actorSlot != UINT32_MAX &&
       actorSlot >= context->nativeScheduleActors.size()) ||
      staticState == 0 || flags == 0 ||
      (flags & ~(TALOS_RT_STATIC_ROOT_READ | TALOS_RT_STATIC_ROOT_WRITE)) != 0)
    return 0;
  if (context->observedWriters &&
      context->observedWriters->rootUsers.count(staticState))
    return 0;
  if (!context->nativeSchedulePlan) {
    // The same per-root fallback is usable by generic fragments. Their
    // ordinary publication path keeps canonical state coherent. A force on
    // one root must not deny direct addressing to unrelated roots.
    const NativeStaticState *state =
        findNativeStaticState(context, staticState);
    return context->nativeStateSpecializationFast && state &&
           !context->observerForcesCanonicalPlane &&
           context->observerDepth == 0 &&
           !nativeMaskIntersectsRange(context->forceMask, state->bitOffset,
                                      state->bitWidth) &&
           !nativeMaskIntersectsRange(context->assignMask, state->bitOffset,
                                      state->bitWidth);
  }
  auto dirty = [&](const std::vector<uint64_t> &mask,
                   const std::unordered_set<uint32_t> &sparse) {
    uint64_t word = staticState / 64;
    return word < mask.size()
               ? (mask[word] & (uint64_t{1} << (staticState % 64))) != 0
               : sparse.find(staticState) != sparse.end();
  };
  auto record = [&](bool fast) {
    if (!context->signalDiagnosticsEnabled)
      return;
    if (fast)
      ++context->signalDiagnostics.aotStateFastPaths;
    else
      ++context->signalDiagnostics.aotStateSlowPaths;
  };
  if (context->nativeScheduleDeoptimized ||
      dirty(context->nativeScheduleTransientDirtyMask,
            context->nativeScheduleTransientDirtyRoots) ||
      dirty(context->nativeSchedulePersistentDirtyMask,
            context->nativeSchedulePersistentDirtyRoots)) {
    record(false);
    return 0;
  }
  if (actorSlot == UINT32_MAX) {
    bool allowed = findNativeStaticState(context, staticState) != nullptr;
    record(allowed);
    return allowed;
  }
  if (actorSlot >= context->nativeScheduleActorRootRanges.size()) {
    record(false);
    return 0;
  }
  auto [begin, end] = context->nativeScheduleActorRootRanges[actorSlot];
  for (uint64_t index = begin; index != end; ++index) {
    const talos_rt_static_actor_root &dependency =
        context->nativeScheduleActorRoots[index];
    if (dependency.static_state == staticState &&
        (dependency.flags & flags) == flags) {
      record(true);
      return 1;
    }
  }
  record(false);
  return 0;
}

#endif
