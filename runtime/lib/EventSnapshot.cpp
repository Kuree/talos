//===- EventSnapshot.cpp - Explicit event-time state transactions --------===//

#include "ProcessContext.h"
#include "ProcessPacking.h"
#include "ProcessShared.h"

#include <algorithm>
#include <new>
#include <stdexcept>
#include <vector>

extern "C" talos_rt_status
talos_rt_v1_event_snapshot_mask(talos_rt_context *context, uint64_t *outMask) {
  if (!context || !outMask)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextMutexLock lock(context);
  if (!context->exactEvents || !context->exactEvents->samplingSnapshot)
    return TALOS_RT_INVALID_LIFECYCLE;
  *outMask = context->exactEvents->snapshotMask;
  return TALOS_RT_OK;
}

namespace {
struct SnapshotUpdate {
  EventSnapshotTarget target;
  std::vector<uint8_t> oldValue, oldUnknown, value, unknown;
  std::vector<uint8_t> changed, posedge, negedge;
  bool differs = false;
};

bool liveSnapshotOwner(const ExactEventFeatureState &feature,
                       const EventSnapshotWork &work) {
  auto found = feature.registrations.find(work.ownerLogicalToken);
  return found != feature.registrations.end() &&
         found->second->snapshotIdentity == work.identity;
}

talos_rt_status stageSnapshotBatch(talos_rt_context *context,
                                   const EventSnapshotBatch &batch,
                                   std::vector<SnapshotUpdate> &updates) {
  // Validate the bound native image before the first write. The shared commit
  // helper subsequently sees these same extents under the context lock.
  uint64_t bits = context->execution->state_bit_count;
  if ((context->nativeStateValue || context->nativeStateUnknown ||
       context->nativeStateBitCount) &&
      (!context->nativeStateValue ||
       (!context->nativeStateUnknown && !context->twoState()) ||
       context->nativeStateBitCount != bits))
    return TALOS_RT_LAYOUT_MISMATCH;
  for (const auto &work : batch) {
    if (!liveSnapshotOwner(*context->exactEvents, work))
      continue;
    uint64_t source = 0;
    for (const auto &target : work.targets) {
      EventSnapshotTarget checked{};
      auto status =
          validateEventSnapshotTargetUnlocked(context, target.abi, checked);
      if (status != TALOS_RT_OK)
        return status;
      if (checked.bitOffset != target.bitOffset ||
          checked.publicationHandle != target.publicationHandle)
        return TALOS_RT_LAYOUT_MISMATCH;
      SnapshotUpdate update;
      update.target = target;
      size_t bytes = static_cast<size_t>((uint64_t{target.abi.width} + 7) / 8);
      update.oldValue.resize(bytes);
      update.oldUnknown.resize(bytes);
      update.value.resize(bytes);
      update.unknown.resize(bytes);
      update.changed.resize(bytes);
      update.posedge.resize(bytes);
      update.negedge.resize(bytes);
      for (uint64_t bit = 0; bit < target.abi.width; bit += 64) {
        uint64_t width = std::min<uint64_t>(64, target.abi.width - bit);
        uint64_t mask = UINT64_MAX >> (64 - width);
        uint64_t at = target.bitOffset + bit;
        uint64_t oldValue = loadPackedBits(context->stateValue, at, width);
        uint64_t oldUnknown = loadPackedBits(context->stateUnknown, at, width);
        uint64_t value = loadPackedBits(work.value, source + bit, width);
        uint64_t unknown = loadPackedBits(work.unknown, source + bit, width);
        if (!(target.abi.flags & TALOS_RT_EVENT_SNAPSHOT_FOUR_STATE)) {
          value &= ~unknown;
          unknown = 0;
        }
        uint64_t changed = ((oldValue ^ value) | (oldUnknown ^ unknown)) & mask;
        uint64_t oldZero = ~oldUnknown & ~oldValue;
        uint64_t oldOne = ~oldUnknown & oldValue;
        uint64_t newZero = ~unknown & ~value;
        uint64_t newOne = ~unknown & value;
        storePackedBytes(update.oldValue.data(), bit, width, oldValue);
        storePackedBytes(update.oldUnknown.data(), bit, width, oldUnknown);
        storePackedBytes(update.value.data(), bit, width, value);
        storePackedBytes(update.unknown.data(), bit, width, unknown);
        storePackedBytes(update.changed.data(), bit, width, changed);
        storePackedBytes(update.posedge.data(), bit, width,
                         changed &
                             ((oldZero & ~newZero) | (oldUnknown & newOne)));
        storePackedBytes(update.negedge.data(), bit, width,
                         changed &
                             ((oldOne & ~newOne) | (oldUnknown & newZero)));
        update.differs |= changed != 0;
      }
      source += target.abi.width;
      updates.push_back(std::move(update));
    }
  }
  return TALOS_RT_OK;
}
} // namespace

extern "C" talos_rt_status
talos_rt_v1_event_snapshot_flush(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return context->schedulerStatus;
    auto *feature = context->exactEvents.get();
    if (!feature)
      return TALOS_RT_OK;
    if (context->observerDepth || context->exactEventEvaluationDepth ||
        feature->dispatchDepth || feature->flushingSnapshots ||
        context->publicationBatch.depth)
      return TALOS_RT_INVALID_LIFECYCLE;
    if (context->nativeSchedulePlan)
      return TALOS_RT_TIER_UNAVAILABLE;
    struct FlushGuard {
      talos_rt_context *context;
      const ClockConditionPublicationView *publication;
      bool canonical;
      ~FlushGuard() {
        context->conditionPublication = publication;
        context->observerForcesCanonicalPlane = canonical;
        auto *feature = context->exactEvents.get();
        feature->collectingSnapshotNotifications = false;
        feature->snapshotOccurrences.clear();
        feature->flushingSnapshots = false;
        if (feature->registrations.empty() && feature->snapshots.empty())
          context->exactEvents.reset();
      }
    } guard{context, context->conditionPublication,
            context->observerForcesCanonicalPlane};
    feature->flushingSnapshots = true;
    context->conditionPublication = nullptr;
    context->observerForcesCanonicalPlane = true;
    // Bound target-triggered cycles without recursively consuming C++ stack.
    // This inventory and budget exist only for users of explicit snapshots.
    constexpr uint64_t maximumBatches = 4096;
    uint64_t processed = 0;
    while (!feature->snapshots.empty()) {
      if (++processed > maximumBatches) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return context->schedulerStatus;
      }
      EventSnapshotBatch batch = std::move(feature->snapshots.front());
      feature->snapshots.pop_front();
      std::vector<SnapshotUpdate> updates;
      auto status = stageSnapshotBatch(context, batch, updates);
      if (status != TALOS_RT_OK)
        return status;
      // IEEE 1801-2018 6.50: all same-event samplers already observed the
      // pre-transaction state. Commit every target before notifying the first
      // one, including packed destinations sharing a canonical limb.
      for (const auto &update : updates) {
        const auto &target = update.target;
        for (uint64_t bit = 0; bit < target.abi.width; bit += 64) {
          uint64_t width = std::min<uint64_t>(64, target.abi.width - bit);
          uint64_t at = target.bitOffset + bit;
          uint64_t value = loadPackedBytes(update.value.data(), bit, width);
          uint64_t unknown = loadPackedBytes(update.unknown.data(), bit, width);
          uint64_t oldUnknown =
              loadPackedBytes(update.oldUnknown.data(), bit, width);
          if (!storeNativeScheduleStateUnlocked(context, at, width, value,
                                                unknown, oldUnknown))
            return TALOS_RT_LAYOUT_MISMATCH;
          storePackedBits(context->stateValue, at, width, value);
          storePackedBits(context->stateUnknown, at, width, unknown);
        }
      }
      feature->collectingSnapshotNotifications = true;
      feature->snapshotOccurrences.clear();
      for (const auto &update : updates) {
        if (!update.differs)
          continue;
        // The transaction is already committed. Replaying an individual
        // target here could rewind a newer update made during notification.
        if (!publishCommittedSignalTransitionUnlocked(
                context, update.target.publicationHandle,
                update.target.abi.width, update.changed.data(),
                update.posedge.data(), update.negedge.data(),
                update.oldValue.data(), update.oldUnknown.data(),
                update.value.data(), update.unknown.data())) {
          if (context->schedulerStatus == TALOS_RT_OK)
            context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
          return context->schedulerStatus;
        }
      }
      feature->collectingSnapshotNotifications = false;
      auto occurrences = std::move(feature->snapshotOccurrences);
      feature->snapshotOccurrences.clear();
      if (!occurrences.empty() &&
          !captureEventSnapshotsUnlocked(context, occurrences, nullptr))
        return context->schedulerStatus;
    }
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}
