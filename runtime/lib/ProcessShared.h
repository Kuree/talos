//===- ProcessShared.h - Process/scheduler internal linkage ----*- C++ -*-===//
//
// Declarations shared between the process/scheduler translation units that
// were split out of Process.cpp (ProcessAOT.cpp, ProcessNBA.cpp,
// ProcessNativeState.cpp).  Everything here has internal-to-libtalos_rt
// linkage; nothing is part of the public runtime ABI.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_PROCESSSHARED_H
#define TALOS_RUNTIME_LIB_PROCESSSHARED_H

#include "GeneratedNBAStorage.h"
#include "ProcessContext.h"
#include "RuntimeInternal.h"

#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <unordered_set>
#include <vector>

constexpr uint64_t kNativeLogicalProcessTag =
    TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG;

extern std::mutex nativeScheduleRegistryMutex;
extern std::unordered_set<const void *> installedNativeScheduleStates;

class NativeAOTMutexScope {
public:
  explicit NativeAOTMutexScope(talos_rt_context *context)
      : previous(lockedNativeAOTContext), lock(context->mutex) {
    lockedNativeAOTContext = context;
  }
  NativeAOTMutexScope(const NativeAOTMutexScope &) = delete;
  NativeAOTMutexScope &operator=(const NativeAOTMutexScope &) = delete;
  ~NativeAOTMutexScope() { lockedNativeAOTContext = previous; }

private:
  talos_rt_context *previous;
  std::unique_lock<TalosContextMutex> lock;
};

class NativeAOTContextScope {
public:
  explicit NativeAOTContextScope(talos_rt_context *context)
      : previous(activeNativeAOTContext) {
    activeNativeAOTContext = context;
  }
  NativeAOTContextScope(const NativeAOTContextScope &) = delete;
  NativeAOTContextScope &operator=(const NativeAOTContextScope &) = delete;
  ~NativeAOTContextScope() { activeNativeAOTContext = previous; }

private:
  talos_rt_context *previous;
};

// An attached reader can register a future boundary without introducing
// work before this slot's NBA cut (4.4, 38.36.2). A scoped writer posts a
// current-time deadline when it actually publishes a value change. Check
// that deadline after each activation and before reusing a cut (38.36.1).
inline bool vpiQuietBeforeNBA(const talos_rt_context *context) {
  if (!context->vpiState)
    return true;
  if (!context->execution ||
      (context->execution->flags &
       (TALOS_RT_EXECUTION_VPI_READ | TALOS_RT_EXECUTION_VPI_WRITE)) !=
          TALOS_RT_EXECUTION_VPI_READ ||
      context->vpiObservationDemand ||
      (context->observedWriters && context->observedWriters->clockHandoff) ||
      context->vpiTimeCallbackActive ||
      (context->preponedSlotHooks &
       (kVPISignalSlotHook | kVPINextTimeSlotHook)))
    return false;
  auto future = [&](std::optional<uint64_t> deadline) {
    return !deadline || *deadline > context->schedulerTime;
  };
  return future(context->nextVPITimeCallback) &&
         future(context->nextVPISyncCallback);
}

// A sufficient test for an installed runtime calendar to own static fanout.
// A publisher that already checked its shared planes, overrides and absence
// of runtime observers need only validate the remaining calendar state.
// A general caller also checks the forwarded assertion certificate: its
// reads at publication time remain valid under that plan (4.5, 9.4.2, 16.12).
template <bool UnobservedSharedSource>
inline bool cleanCalendarOwnsFanout(const talos_rt_context *context) {
  const auto *plan = context->nativeSchedulePlan;
  if (!plan || !context->execution || context->nativeScheduleDeoptimized ||
      !(plan->flags & TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL) ||
      !(plan->flags & (TALOS_RT_NATIVE_SCHEDULE_STATIC_FANOUT |
                       TALOS_RT_NATIVE_SCHEDULE_GUARDED_FANOUT)))
    return false;
  bool forwarded =
      plan->flags & TALOS_RT_NATIVE_SCHEDULE_FORWARDED_ASSERTION_INPUTS;
  if constexpr (!UnobservedSharedSource) {
    if (!forwarded ||
        !(plan->flags & TALOS_RT_NATIVE_SCHEDULE_ASSERTION_OBSERVERS) ||
        context->vpiObservationDemand || context->exactEvents ||
        !context->forceMask.empty() || !context->assignMask.empty() ||
        !context->nativeConditionalSignalWaiters.empty() ||
        !context->designConditionalSignalWaiters.empty())
      return false;
  }
  return !context->nativeScheduleStopAtCleanBoundary &&
         !context->nativeScheduleExternalWritePending &&
         !context->nativeScheduleDirtyRootsPresent &&
         !(context->observedWriters &&
           context->observedWriters->clockHandoff) &&
         context->scheduledDesignTasks.empty() &&
         ((!context->activeComputedObserverWaiterCount &&
           !context->nativeDynamicSignalSubscriptions) ||
          (forwarded && context->nativeDynamicSignalSubscriptions ==
                            context->nativeComputedSignalSubscriptions));
}

inline bool isStaticControlAOT(const talos_rt_context *context) {
  return activeNativeAOTContext == context && context->nativeSchedulePlan &&
         (context->nativeSchedulePlan->flags &
          TALOS_RT_NATIVE_SCHEDULE_STATIC_CONTROL) != 0;
}

//===----------------------------------------------------------------------===//
// Process frame bookkeeping (Process.cpp)
//===----------------------------------------------------------------------===//

void unregisterManagedFrameRoots(talos_rt_process_instance_v1 *instance);
/// Whether `instance` was created at its wait (TALOS_RT_SPAWN_STARTED) and
/// its body has not run yet.
bool hasPendingProcessStart(talos_rt_process_instance_v1 *instance);
/// Under signal diagnostics, counts an execution of a started (admitted)
/// owner's process body; an entry replay is not an activation.
void countStartedOwnerBodyActivation(talos_rt_process_instance_v1 *instance,
                                     talos_rt_context *context);
/// Before such an instance first executes in `tier`, runs the entry its
/// creation skipped. Afterwards the instance is exactly where its first
/// activation would have left it, or (TIME_ZERO) at its entry.
talos_rt_status replayPendingProcessStart(talos_rt_process_instance_v1 *instance,
                                          talos_rt_context *context,
                                          talos_rt_execution_tier tier);
void releaseOwnedNativeStates(talos_rt_context *context,
                              talos_rt_process_instance_v1 *instance);

//===----------------------------------------------------------------------===//
// Native state planes and dirty-root tracking (ProcessNativeState.cpp)
//===----------------------------------------------------------------------===//

const NativeStaticState *findNativeStaticState(const talos_rt_context *context,
                                               uint32_t id);
// These leaf accesses also serve bytecode publication and NBA boundaries.
// Keep their bodies visible to callers without requiring whole-runtime LTO.
inline bool byteBit(const uint8_t *bytes, uint64_t bit) {
  return bytes && (bytes[bit / 8] & static_cast<uint8_t>(1u << (bit % 8))) != 0;
}

inline void setByteBit(uint8_t *bytes, uint64_t bit, bool value) {
  if (!bytes)
    return;
  uint8_t mask = static_cast<uint8_t>(1u << (bit % 8));
  if (value)
    bytes[bit / 8] |= mask;
  else
    bytes[bit / 8] &= static_cast<uint8_t>(~mask);
}
bool nativeMaskIntersectsRange(const std::vector<uint64_t> &mask,
                               uint64_t bitOffset, uint64_t bitWidth);
bool importNativeStatePlanesUnlocked(talos_rt_context *context,
                                     const uint8_t *value,
                                     const uint8_t *unknown, uint64_t bitCount);
bool importNativeRootInitializerPlanesUnlocked(talos_rt_context *context);
bool exportNativeStatePlanesUnlocked(const talos_rt_context *context,
                                     uint8_t *value, uint8_t *unknown,
                                     uint64_t bitCount);
bool reconcileNativeRootToPlanesUnlocked(
    const talos_rt_context *context, const talos_rt_native_schedule_plan *plan,
    uint32_t id);
bool reconcileNativeDirtyRootsToPlanesUnlocked(
    const talos_rt_context *context, const talos_rt_native_schedule_plan *plan);
bool nativeStaticRootDirty(const talos_rt_context *context,
                           uint32_t staticState);
bool nativeStaticSpecializationEnvironmentClean(
    const talos_rt_context *context);
bool nativePeriodicAOTEnvironmentClean(const talos_rt_context *context);
void markNativeDirtyRootUnlocked(talos_rt_context *context, uint32_t id,
                                 bool persistent);
void clearNativeDirtyRootUnlocked(talos_rt_context *context, uint32_t id,
                                  bool persistent);
void invalidateNativeStaticSpecializationFastUnlocked(
    talos_rt_context *context);
void invalidateNativeTwoStatePromotionUnlocked(talos_rt_context *context);
void invalidateNativeTwoStatePromotionRangeUnlocked(talos_rt_context *context,
                                                    uint64_t bitOffset,
                                                    uint64_t bitWidth);
void publishNativeKnownnessChangeUnlocked(
    const talos_rt_native_schedule_plan *plan, uint64_t bitOffset,
    uint64_t bitWidth, uint64_t oldUnknown, uint64_t newUnknown);
// The generated unknown summary: every runtime write into the generated
// unknown plane reports the roots it may have made differ from their
// patterns before generated code runs again. `Range` marks every root it
// overlaps; `Bits` marks only the roots whose pattern differs from `unknown`
// (bit 0 at `bitOffset`, at most 64 bits) in a `written` bit.
void markNativeUnknownRangeUnlocked(const talos_rt_context *context,
                                    uint64_t bitOffset, uint64_t bitWidth);
void markNativeUnknownBitsUnlocked(const talos_rt_context *context,
                                   uint64_t bitOffset, uint64_t bitWidth,
                                   uint64_t unknown,
                                   uint64_t written = UINT64_MAX);
void markNativeUnknownAllUnlocked(const talos_rt_context *context);
/// Whether every write the design-bytecode interpreter makes to design state
/// reports its own bit range to the generated unknown summary and promotion
/// certificates (talos_rt_sync_native_state_range_unlocked and the commit
/// helpers). True when the canonical planes are the generated planes: no
/// copy separates them, so the per-write reports are complete and a bytecode
/// activation needs no whole-plane invalidation (two-tier B1).
bool designBytecodeReportsWritesUnlocked(const talos_rt_context *context);
void verifyNativeUnknownSummaryUnlocked(const talos_rt_context *context);
void refreshNativeStaticSpecializationFastUnlocked(talos_rt_context *context);
bool storeNativeScheduleStateUnlocked(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    uint64_t value, uint64_t unknown,
    std::optional<uint64_t> previousUnknown = std::nullopt);

//===----------------------------------------------------------------------===//
// Scheduler queue maintenance (Process.cpp)
//===----------------------------------------------------------------------===//

inline bool isReactiveSchedulerRegion(uint32_t region) {
  return region >= TALOS_RT_REGION_REACTIVE && region <= TALOS_RT_REGION_RE_NBA;
}

inline bool schedulerRegionEligible(const talos_rt_context *context,
                                    uint32_t region) {
  return !context->schedulerDrainingReactive ||
         isReactiveSchedulerRegion(region);
}

inline uint32_t nativeNBABarrierLowerBound(const talos_rt_context *context) {
  // IEEE 1800-2023 4.4.2.4, 4.4.2.8: the compiler's runtime-calendar
  // certificate stages static roots only in NBA/Re-NBA. Keep the general
  // inventory contract for plans without that compiler proof.
  bool certified = context->nativeSchedulePlan &&
                   (context->nativeSchedulePlan->flags &
                    TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL);
  if (context->schedulerDrainingReactive)
    return certified ? TALOS_RT_REGION_RE_NBA : TALOS_RT_REGION_REACTIVE;
  return certified ? TALOS_RT_REGION_NBA : TALOS_RT_REGION_ACTIVE;
}

inline void setSchedulerDrainingReactive(talos_rt_context *context,
                                         bool draining) {
  if (context->schedulerDrainingReactive == draining)
    return;
  context->schedulerDrainingReactive = draining;
  // Both native and bytecode ready caches depend on region eligibility.
  if (++context->schedulerSelectionGeneration == 0)
    context->schedulerSelectionGeneration = 1;
}

bool nativeProcessReady(talos_rt_context &context,
                        const ScheduledProcess &process);
inline const talos_rt_wait_record_v1 *
designTaskCurrentWait(const ScheduledDesignTask &task) {
  if (task.waitSize < sizeof(talos_rt_wait_record_v1) ||
      task.waitOffset > task.frame.size() ||
      task.waitSize > task.frame.size() - task.waitOffset)
    return nullptr;
  return reinterpret_cast<const talos_rt_wait_record_v1 *>(task.frame.data() +
                                                           task.waitOffset);
}
inline uint32_t designTaskOrderingRegion(const ScheduledDesignTask &task,
                                         bool signalResume) {
  if (signalResume &&
      talos_rt_is_slot_final_clock_occurrence_wait(designTaskCurrentWait(task)))
    return TALOS_RT_REGION_POSTPONED;
  return task.queuedRegion == TALOS_RT_REGION_POSTPONED
             ? TALOS_RT_REGION_POSTPONED + 1
             : task.queuedRegion;
}
void indexScheduledProcessDelayUnlocked(talos_rt_context *context,
                                        const ScheduledProcess &process);
std::optional<uint64_t>
nextScheduledProcessDelayUnlocked(talos_rt_context *context);
void rebuildNativeSchedulerIndexUnlocked(talos_rt_context *context);
uint32_t nativeAOTContinuationRank(const ScheduledProcess &scheduled,
                                   uint32_t continuation);
void updateNativeAOTContinuationRank(ScheduledProcess &scheduled,
                                     uint32_t continuation);
talos_rt_status
adoptScheduledSuspendUnlocked(talos_rt_context *context,
                              ScheduledProcess &scheduled,
                              const talos_rt_fragment_action_v1 &action);
struct SchedulerRunOptions {
  // Select installed compiled executors for plan-owned actors. Other actors
  // and design tasks still execute under the same region arbitration.
  bool nativePlan = false;
  // A generated boundary may retain future clock deadlines. This restricts
  // time advancement, not which runnable regions the shared loop drains.
  bool currentSlotOnly = false;
  // A periodic checkpoint drain: the scheduler cannot call the coordinator,
  // because a coordinator that reaches another cold branch publishes its
  // checkpoint for a generated trampoline to queue. Return as soon as
  // generated ingress is pending, or at the eval cut that a yielded
  // coordinator waits for; the plan entry's next preparation drain calls the
  // coordinator, before other runtime work.
  bool returnGeneratedIngress = false;
  // A generated eval continuation stays on the stack. Drain Active/Inactive
  // work and return before the common NBA barrier instead of reentering it.
  bool stopBeforeNBA = false;
  // A generated transaction may hold its NBA captures locally. Include that
  // region in the same arbitration even when the canonical dirty set is empty.
  uint32_t localPendingNBARegion = UINT32_MAX;
  // Finish exactly one already-started generated NBA barrier. Its compiled
  // prefix has run, so only the remaining runtime queues may execute here.
  uint32_t completeNBABarrier = UINT32_MAX;
  bool generatedNBAChanged = false;
  // Only write-capable private continuations request this foreign-code cut.
  // Their canonical wrapper must export before an unscoped actor executes.
  // Use trailing padding: exceeding 16 bytes makes AArch64 pass the whole
  // options argument indirectly, taxing off/read calls as well.
  bool stopBeforeUnscopedActors = false;
};
static_assert(sizeof(SchedulerRunOptions) <= 16);
talos_rt_status runScheduler(talos_rt_context *context,
                             SchedulerRunOptions options = {},
                             bool *drainedIdle = nullptr);
talos_rt_status executeNativeAOTNodeUnlocked(talos_rt_context *context,
                                             uint32_t actorSlot);
talos_rt_status runPreponedHooks(talos_rt_context *context,
                                 talos_rt_sampled_plane_copy copy = nullptr);
// Initialize the current slot once, regardless of which executor entered it.
// Reentry in the same slot preserves its sampled state and progress cursor.
talos_rt_status
enterSchedulerTimeSlotUnlocked(talos_rt_context *context,
                               talos_rt_sampled_plane_copy copy = nullptr);
talos_rt_status retireInvalidPowerNBAsUnlocked(talos_rt_context *context);
bool powerNBAAllowedUnlocked(talos_rt_context *context, uint64_t sequence,
                             uint8_t half);
// Freeze a ready Inactive/Re-Inactive batch before restarting arbitration.
talos_rt_status promoteInactiveResumptionsUnlocked(talos_rt_context *context,
                                                   uint32_t region);
inline uint32_t schedulerCohortRegion(uint32_t region) {
  if (region == TALOS_RT_REGION_INACTIVE)
    return TALOS_RT_REGION_ACTIVE;
  if (region == TALOS_RT_REGION_RE_INACTIVE)
    return TALOS_RT_REGION_REACTIVE;
  return region;
}
inline bool isInactiveSchedulerRegion(uint32_t region) {
  return region == TALOS_RT_REGION_INACTIVE ||
         region == TALOS_RT_REGION_RE_INACTIVE;
}
// IEEE 1800-2023 4.5: Inactive events move to Active as one set, so a later #0
// cannot overtake a pending sibling of the current batch; that sets `retry`, as
// selection must restart. IEEE 1801-2018 6.50/9.7: otherwise begin the cohort
// of the work about to run in `region` if cohorts are tracked. Primed children
// never come here and stay in their parent's cohort.
talos_rt_status admitSchedulerRegionUnlocked(talos_rt_context *context,
                                             uint32_t region, bool &retry);
talos_rt_status nextSchedulerCohortUnlocked(talos_rt_context *context,
                                            uint32_t region);
bool hasSameDirectSignalWait(const ScheduledProcess &scheduled,
                             const talos_rt_wait_record_v1 *wait);
uint32_t nextDueNBABarrierRegionUnlocked(const talos_rt_context *context,
                                         bool includeGenerated = true);

//===----------------------------------------------------------------------===//
// Signal fanout and transitions (Process.cpp)
//===----------------------------------------------------------------------===//

bool canUseStaticAOTFanout(const talos_rt_context *context);
bool canUseIndexedExternalAOTFanout(const talos_rt_context *context);
bool nativeAOTTransientBoundaryClean(const talos_rt_context *context);
bool validNativeStatePlanesUnlocked(const talos_rt_context *context,
                                    const uint8_t *value,
                                    const uint8_t *unknown, uint64_t bitCount);
void indexNativeFanoutWindows(talos_rt_context &context,
                              const talos_rt_static_fanout_entry *entries);
void indexScalarNBAFanout(talos_rt_context &context,
                          const talos_rt_static_fanout_entry *entries);
bool publishScalarNBAChangeUnlocked(talos_rt_context *context,
                                    uint64_t stableID, uint64_t width,
                                    uint64_t changed, uint64_t posedge,
                                    uint64_t negedge);
class NativeNBAUpdateScope {
public:
  explicit NativeNBAUpdateScope(talos_rt_context &context)
      : applying(context.schedulerApplyingNativeUpdate), previous(applying) {
    applying = true;
  }
  ~NativeNBAUpdateScope() { applying = previous; }

private:
  bool &applying;
  bool previous;
};
size_t replayPackedFIFOPrefixUnlocked(talos_rt_context *context,
                                      uint32_t region, size_t start,
                                      bool &changed, bool &knownnessChange);
bool publishStaticAOTSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t *outSequence, bool indexedExternalDeposit = false);
// `establishesOverride` marks the publication that installs a force or assign
// procedural continuous assignment. Every other publication is filtered
// against the override masks; that one is the write the masks describe.
bool publishNativeSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    const uint8_t *oldValue, const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown, bool establishesOverride = false,
    bool generatedIngress = false);
// Notify an already committed packed update without replaying its state.
bool publishCommittedSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    const uint8_t *oldValue, const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown);
talos_rt_status validateEventSnapshotTargetUnlocked(
    talos_rt_context *context, const talos_rt_event_snapshot_target_v1 &target,
    EventSnapshotTarget &resolved);
talos_rt_status registerExactEvent(
    talos_rt_context *context,
    const talos_rt_computed_wait_record_v1 *eventPlan, uint64_t eventPlanSize,
    uint32_t expectedStrobe, uint64_t observerCodeUnit,
    const talos_rt_computed_capture_v1 *captures, uint32_t captureCount,
    const talos_rt_event_snapshot_target_v1 *targets, uint32_t targetCount,
    decltype(&talos_rt_v1_event_snapshot_flush) snapshotFlush = nullptr);
bool captureEventSnapshotsUnlocked(
    talos_rt_context *context,
    const std::vector<EventSnapshotOccurrence> &occurrences,
    const ClockConditionPublicationView *sample);
void publishOverrideTransition(talos_rt_context *context, uint64_t bitOffset,
                               uint64_t bitWidth, const uint8_t *oldValue,
                               const uint8_t *oldUnknown,
                               const uint8_t *newValue,
                               const uint8_t *newUnknown);
void wakeMonitorProcessUnlocked(talos_rt_context *context,
                                uint64_t logicalToken);

//===----------------------------------------------------------------------===//
// AOT deadline heap and readiness (ProcessAOT.cpp)
//===----------------------------------------------------------------------===//

bool markNativeAOTActorReadyUnlocked(talos_rt_context *context,
                                     uint32_t actorSlot);
/// Arms the actors created at their wait once the root initializer has
/// finished, and raises the time-zero ready bit of each TIME_ZERO owner.
talos_rt_status armStartedNativeAOTActorsUnlocked(talos_rt_context *context);
/// Drops the arming index of the merged fragments (plan release/install).
void clearNativeAOTMergedFragmentIndexUnlocked(talos_rt_context *context);
talos_rt_status suspendNativeAOTTaskCallerUnlocked(talos_rt_context *context,
                                                   ScheduledProcess &scheduled);
void clearNativeAOTNodeReadyUnlocked(talos_rt_context *context, uint32_t node);
void setNativeAOTDeadlineUnlocked(talos_rt_context *context, uint32_t actorSlot,
                                  uint64_t deadline);
void removeNativeAOTDeadlineUnlocked(talos_rt_context *context,
                                     uint32_t actorSlot);
bool markDueNativeAOTDeadlinesUnlocked(talos_rt_context *context);
uint32_t findNativeAOTNodeUnlocked(const talos_rt_context *context,
                                   uint32_t actorSlot, uint32_t continuation);
talos_rt_status refreshNativeAOTReadyPhaseUnlocked(talos_rt_context *context);
talos_rt_status
initializeNativeAOTNodesUnlocked(talos_rt_context *context,
                                 const talos_rt_native_schedule_node *nodes,
                                 uint32_t nodeCount);
bool nativeClockOccurrencePrimaryReadsGeneratedState(
    const talos_rt_context *context,
    const std::unordered_set<uint32_t> &generatedWritableStates);

//===----------------------------------------------------------------------===//
// Non-blocking assignment staging and commit (ProcessNBA.cpp)
//===----------------------------------------------------------------------===//

// Shared native pending-update selection for every execution policy. With an
// installed dirty index, retained generated payloads are not pending work.
uint32_t nextDueNativeNBABarrierRegionUnlocked(const talos_rt_context *context,
                                               bool includeGenerated);

bool hasGeneratedNBAStages(const GeneratedNBAStorage &generated);
bool hasGeneratedNBASlots(const talos_rt_static_nba_root &root);
void markStaticNBAAccumulatorPending(talos_rt_context *context,
                                     uint32_t rootIndex,
                                     StaticNBAAccumulator &accumulator);
void refreshStaticNBAAccumulatorsPending(talos_rt_context *context);
bool staticNBARootNeedsTransitions(const talos_rt_context *context,
                                   uint32_t rootIndex);
talos_rt_status commitStaticNBAAccumulatorsUnlocked(talos_rt_context *context,
                                                    uint32_t barrierRegion,
                                                    bool &changed);
talos_rt_status resolveClockingDriveConflictsUnlocked(talos_rt_context *context,
                                                      uint32_t barrierRegion);
talos_rt_status materializeGeneratedNBAAccumulatorUnlocked(
    talos_rt_context *context, uint32_t rootIndex, uint32_t execRegion);

namespace talos::process {
struct ValidatedSuspension;
}
/// The validated-suspension cache slot of a runtime-allocated process
/// instance (two-tier B2 Q6).
std::unique_ptr<talos::process::ValidatedSuspension> *
processValidatedSuspension(talos_rt_process_instance_v1 *instance);

#endif // TALOS_RUNTIME_LIB_PROCESSSHARED_H
