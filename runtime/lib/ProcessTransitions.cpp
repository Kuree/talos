//===- ProcessTransitions.cpp - Signal occurrence publication ------------===//
//
// Publication of signal occurrences and value transitions: subscription
// matching and wakeup, the indexed and static AOT fanout fast paths, and the
// scheduler entry points generated code calls to report signal, static, real,
// and event transitions.  Split out of Process.cpp.
//
//===----------------------------------------------------------------------===//

#include "ProcessAllocation.h"
#include "ProcessContext.h"
#include "ProcessObservers.h"
#include "ProcessPacking.h"
#include "ProcessShared.h"
#include "ProcessSignals.h"
#include "ProcessValidation.h"
#include "RuntimeInternal.h"
#include "SignalSemantics.h"
#include "VPIValueChange.h"
#include "talos/Runtime/ClockKernelReadySet.h"
#include "talos/Runtime/StableHandle.h"
#include "talos/Runtime/StableHash.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <limits>
#include <memory>
#include <new>
#include <optional>
#include <stdexcept>
#include <tuple>

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#endif

using namespace talos::process;
using namespace talos::runtime;

bool talos_rt_read_signal_bit_unlocked(talos_rt_context *context,
                                       uint64_t stableID, uint64_t bit,
                                       bool &value, bool &unknown,
                                       bool useSnapshot) {
  value = false;
  unknown = false;
  if (!context || stableID == UINT64_MAX)
    return false;
  talos_rt_stable_handle_v1 decoded;
  if (!talos_rt_stable_handle_decode(stableID, &decoded) ||
      decoded.offset < 0 || bit > uint64_t{INT64_MAX})
    return false;
  uint64_t relative = static_cast<uint64_t>(decoded.offset) + bit;
  if (relative < static_cast<uint64_t>(decoded.offset))
    return false;
  uint64_t indexed =
      talos_rt_stable_handle_offset(stableID, static_cast<int64_t>(bit));
  auto snapshot = !useSnapshot || indexed == UINT64_MAX
                      ? context->signalValueSnapshots.end()
                      : context->signalValueSnapshots.find(indexed);
  if (snapshot != context->signalValueSnapshots.end()) {
    value = snapshot->second.value;
    unknown = snapshot->second.unknown;
    return true;
  }
  if (decoded.kind == TALOS_RT_STABLE_HANDLE_AUTOMATIC) {
    auto found = context->nativeAutomaticStates.find(decoded.id);
    if (found == context->nativeAutomaticStates.end() ||
        relative >= found->second.bitWidth)
      return false;
    value = !found->second.value.empty() &&
            ((found->second.value[relative / 8] >> (relative % 8)) & 1) != 0;
    unknown =
        !found->second.unknown.empty() &&
        ((found->second.unknown[relative / 8] >> (relative % 8)) & 1) != 0;
    return true;
  }
  uint64_t absolute = relative;
  if (decoded.kind == TALOS_RT_STABLE_HANDLE_STATIC) {
    const NativeStaticState *storage =
        findNativeStaticState(context, decoded.id);
    if (!storage || relative >= storage->bitWidth)
      return false;
    absolute = storage->bitOffset + relative;
  } else if (decoded.kind != TALOS_RT_STABLE_HANDLE_GLOBAL) {
    return false;
  }
  if (absolute >= context->stateValue.size() * uint64_t{64} ||
      absolute >= context->stateUnknown.size() * uint64_t{64})
    return false;
  uint64_t mask = uint64_t{1} << (absolute % 64);
  value = (context->stateValue[absolute / 64] & mask) != 0;
  unknown = (context->stateUnknown[absolute / 64] & mask) != 0;
  return true;
}

namespace {

void finalizeClockOccurrenceWave(ClockOccurrenceWaitState &state) {
  if (!state.hasCurrentKey)
    return;
  state.finalizedCohorts.insert(state.finalizedCohorts.end(),
                                state.currentCohorts.begin(),
                                state.currentCohorts.end());
  state.currentCohorts.clear();
  state.occurrenceCounts.fill(0);
  state.hasCurrentKey = false;
}

constexpr size_t kMaximumNoChangePendingEntries = size_t{1} << 20;

bool addNoChangeCount(talos_rt_context *context, uint64_t &target,
                      uint64_t increment) {
  if (increment > std::numeric_limits<uint64_t>::max() - target) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  target += increment;
  return true;
}

bool noChangeContains(const NoChangeClosedWindow &window, uint64_t time) {
  __int128 wide = static_cast<__int128>(time);
  return window.begin < wide && wide < window.end;
}

void pruneNoChangeData(NoChangeCheckState &state, uint64_t now) {
  __int128 futureBegin =
      static_cast<__int128>(now) - std::max<int64_t>(state.startOffset, 0);
  __int128 oldestBegin =
      state.open ? std::min(state.openBegin, futureBegin) : futureBegin;
  while (state.dataBegin != state.data.size() &&
         static_cast<__int128>(state.data[state.dataBegin].time) <= oldestBegin)
    ++state.dataBegin;
  if (state.open)
    state.openDataBegin = std::max(state.openDataBegin, state.dataBegin);
  if (state.dataBegin >= 1024 && state.dataBegin * 2 >= state.data.size()) {
    size_t erased = state.dataBegin;
    state.data.erase(state.data.begin(), state.data.begin() + state.dataBegin);
    state.dataBegin = 0;
    if (state.open)
      state.openDataBegin -= std::min(state.openDataBegin, erased);
  }
}

bool recordNoChangeData(talos_rt_context *context, NoChangeCheckState &state,
                        uint64_t now) {
  for (const NoChangeClosedWindow &window : state.windows)
    if (noChangeContains(window, now) &&
        !addNoChangeCount(context, state.pendingReports, window.multiplicity))
      return false;
  if (!state.data.empty() && state.data.back().time == now)
    return addNoChangeCount(context, state.data.back().count, 1);
  if (state.data.size() - state.dataBegin >= kMaximumNoChangePendingEntries) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  state.data.push_back({now, 1});
  return true;
}

bool closeNoChangeWindow(talos_rt_context *context, NoChangeCheckState &state,
                         uint64_t now) {
  if (!state.open)
    return true;
  NoChangeClosedWindow closed{state.openBegin,
                              static_cast<__int128>(now) + state.endOffset, 1};
  state.open = false;
  if (closed.begin >= closed.end)
    return true;
  for (size_t index = std::max(state.dataBegin, state.openDataBegin);
       index != state.data.size(); ++index)
    if (noChangeContains(closed, state.data[index].time) &&
        !addNoChangeCount(context, state.pendingReports,
                          state.data[index].count))
      return false;
  if (closed.end <= static_cast<__int128>(now))
    return true;
  for (NoChangeClosedWindow &window : state.windows)
    if (window.begin == closed.begin && window.end == closed.end)
      return addNoChangeCount(context, window.multiplicity, 1);
  if (state.windows.size() >= kMaximumNoChangePendingEntries) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  state.windows.push_back(closed);
  return true;
}

bool finalizeNoChangeOpenWindow(talos_rt_context *context,
                                NoChangeCheckState &state) {
  if (!state.open || state.endOffset < 0)
    return true;
  // IEEE 1800-2017 31.4.6 makes data after the open beginning certain as soon
  // as a complete numeric slot has no trailing edge: a future trailing edge
  // plus a nonnegative end offset must lie later. Clause 31.6 therefore
  // publishes these reports now, including positive-start history discovered
  // by the leading edge, instead of delaying the notifier until the trailing
  // edge. Only a negative end offset remains genuinely uncertain.
  for (size_t index = std::max(state.dataBegin, state.openDataBegin);
       index != state.data.size(); ++index) {
    const NoChangeDataOccurrence &data = state.data[index];
    if (state.openBegin < static_cast<__int128>(data.time) &&
        !addNoChangeCount(context, state.pendingReports, data.count))
      return false;
  }
  state.openDataBegin = state.data.size();
  return true;
}

bool locateClockPublicationBit(const ClockConditionPublicationView *sample,
                               uint64_t stableID, uint64_t &planeBit) {
  if (!sample || sample->bitWidth == 0)
    return false;
  talos_rt_stable_handle_v1 published;
  talos_rt_stable_handle_v1 conditioned;
  if (!talos_rt_stable_handle_decode(sample->stableID, &published) ||
      !talos_rt_stable_handle_decode(stableID, &conditioned) ||
      published.offset < 0 || conditioned.offset < 0 ||
      published.kind != conditioned.kind ||
      (published.kind != TALOS_RT_STABLE_HANDLE_GLOBAL &&
       published.id != conditioned.id))
    return false;
  __int128 bit = static_cast<__int128>(conditioned.offset) - published.offset;
  if (bit < 0 || bit >= sample->bitWidth ||
      bit > UINT64_MAX - sample->planeBitOffset)
    return false;
  planeBit = sample->planeBitOffset + static_cast<uint64_t>(bit);
  return true;
}

class ClockConditionPublicationOverlay {
public:
  ClockConditionPublicationOverlay(talos_rt_context *context,
                                   const ClockConditionPublicationView *sample)
      : context(context),
        previousCanonicalPlane(context->observerForcesCanonicalPlane),
        previousPublication(context->conditionPublication) {
    context->observerForcesCanonicalPlane = true;
    if (sample) {
      publication = *sample;
      publication.previous = context->conditionPublication;
      context->conditionPublication = &publication;
    }
  }

  ClockConditionPublicationOverlay(const ClockConditionPublicationOverlay &) =
      delete;
  ClockConditionPublicationOverlay &
  operator=(const ClockConditionPublicationOverlay &) = delete;

  ~ClockConditionPublicationOverlay() {
    context->conditionPublication = previousPublication;
    context->observerForcesCanonicalPlane = previousCanonicalPlane;
    if (context->nativeStateSpecializationFast)
      refreshNativeStaticSpecializationFastUnlocked(context);
  }

private:
  talos_rt_context *context = nullptr;
  bool previousCanonicalPlane = false;
  const ClockConditionPublicationView *previousPublication = nullptr;
  ClockConditionPublicationView publication;
};

bool readClockOccurrenceCondition(talos_rt_context *context,
                                  const ClockOccurrenceCondition &condition,
                                  const ClockConditionPublicationView *sample,
                                  uint64_t waiterToken, bool native) {
  if (!context)
    return false;
  if (!condition.isObserver() &&
      (condition.stableID == UINT64_MAX || condition.width == 0))
    return condition.stableID == UINT64_MAX;
  uint32_t predicate = condition.predicate;
  uint64_t value = 0;
  uint64_t unknown = 0;
  // IEEE 1800-2017 31.7 uses only the LSB when the conditioning net or
  // expression is multibit. Sampling one bit also keeps this event hot path
  // independent of the declared vector width.
  // IEEE 1800-2017 31.7 samples the condition in the controlled event. A
  // generated AOT plane may already contain later source stores, while its
  // canonical mirror can still precede this publication. Use only this
  // publication's transient post-transition plane when the condition aliases
  // it; otherwise retain the ordinary live read. This state is pay-for-play
  // and never enters an ABI record or a persistent lookup table.
  if (condition.isObserver()) {
    // IEEE 1800-2017 31.7 samples the complete expression in the controlled
    // event. Native publication intentionally trails generated stores, so the
    // compiled observer gets a scoped post-transition canonical overlay. It
    // exists only on this computed-condition path and is restored by RAII even
    // when an evaluator reports or throws; ordinary signal loads and direct
    // timing conditions retain their allocation-free ABI and hot path.
    ClockConditionPublicationOverlay overlay(context, sample);
    bool evaluated =
        native ? talos_rt_evaluate_native_clock_condition_unlocked(
                     context, waiterToken, condition.observerCodeUnitID,
                     condition.observerCaptures.data(),
                     condition.observerCaptures.size(), value, unknown)
               : talos_rt_evaluate_design_clock_condition_unlocked(
                     context, waiterToken, condition.observerCodeUnitID,
                     condition.observerCaptures.data(),
                     condition.observerCaptures.size(), value, unknown);
    if (!evaluated)
      return false;
  } else {
    uint64_t publicationBit = 0;
    bool aliasesPublication =
        locateClockPublicationBit(sample, condition.stableID, publicationBit);
    bool bitValue = false;
    bool bitUnknown = false;
    if (aliasesPublication && sample->newValue) {
      bitValue = byteBit(sample->newValue, publicationBit);
      bitUnknown =
          sample->newUnknown && byteBit(sample->newUnknown, publicationBit);
    } else if (!talos_rt_read_signal_bit_unlocked(
                   context, condition.stableID, 0, bitValue, bitUnknown,
                   /*useSnapshot=*/!aliasesPublication)) {
      return false;
    }
    value = bitValue;
    unknown = bitUnknown;
  }
  // IEEE 1800-2017 31.7 explicitly distinguishes nondeterministic ==/!=
  // from deterministic forms: any X enables the former and disables the
  // latter. The direct packed handle is sampled in this publication, never
  // reconstructed later from an Observed-region live value.
  switch (predicate) {
  case TALOS_RT_WAIT_CONDITION_KNOWN_ONE:
    return !unknown && value;
  case TALOS_RT_WAIT_CONDITION_KNOWN_ZERO:
    return !unknown && !value;
  case TALOS_RT_WAIT_CONDITION_LOGICAL_EQ_ZERO:
    return unknown || !value;
  case TALOS_RT_WAIT_CONDITION_LOGICAL_EQ_ONE:
    return unknown || value;
  case TALOS_RT_WAIT_CONDITION_LOGICAL_NE_ZERO:
    return unknown || value;
  case TALOS_RT_WAIT_CONDITION_LOGICAL_NE_ONE:
    return unknown || !value;
  case TALOS_RT_WAIT_CONDITION_CASE_EQ_ZERO:
    return !unknown && !value;
  case TALOS_RT_WAIT_CONDITION_CASE_EQ_ONE:
    return !unknown && value;
  case TALOS_RT_WAIT_CONDITION_CASE_NE_ZERO:
    return !unknown && value;
  case TALOS_RT_WAIT_CONDITION_CASE_NE_ONE:
    return !unknown && !value;
  default:
    return false;
  }
}

bool evaluateExactEventsNowUnlocked(
    talos_rt_context *context, uint64_t sequence, uint32_t dependencyKind,
    uint32_t kind, uint32_t objectID, int64_t firstPage, int64_t lastPage,
    uint64_t stableID, uint64_t bitWidth,
    const ClockConditionPublicationView *sample) {
  ExactEventFeatureState *feature = context->exactEvents.get();
  if (!feature)
    return true;
  struct Candidate {
    uint64_t ownerLogicalToken = 0;
    uint32_t clauseIndex = 0;
  };
  std::vector<Candidate> candidates;
  std::vector<uint64_t> sampleOwners;
  std::vector<EventSnapshotOccurrence> snapshotOwners;
  auto physicalRange = [&](uint64_t handle, uint64_t width, __int128 &begin,
                           __int128 &end) {
    talos_rt_stable_handle_v1 decoded{};
    if (!talos_rt_stable_handle_decode(handle, &decoded))
      return false;
    begin = decoded.offset;
    if (decoded.kind == TALOS_RT_STABLE_HANDLE_STATIC) {
      const auto *state = findNativeStaticState(context, decoded.id);
      if (!state)
        return false;
      begin += state->bitOffset;
    } else if (decoded.kind != TALOS_RT_STABLE_HANDLE_GLOBAL) {
      return false;
    }
    end = begin + width;
    return true;
  };
  auto considerClause = [&](ExactEventClause *clause) {
    if (!clause || clause->lastExaminedSequence == sequence)
      return;
    if (context->signalDiagnosticsEnabled)
      ++context->signalDiagnostics.subscribersExamined;
    if (!clause->registration)
      return;
    auto *plan = reinterpret_cast<talos_rt_computed_wait_record_v1 *>(
        clause->registration->eventPlan.data());
    auto *observers = computedWaitSpan<talos_rt_computed_observer_v1>(
        plan, plan->observers_offset, plan->observer_count);
    auto *dependencies = computedWaitSpan<talos_rt_computed_dependency_v1>(
        plan, plan->dependencies_offset, plan->dependency_count);
    if (!observers || !dependencies ||
        clause->clauseIndex >= plan->clause_count)
      return;
    const auto &primary = observers[clause->clauseIndex];
    bool affected = false;
    for (uint32_t dependencyIndex = 0;
         dependencyIndex != primary.dependency_count; ++dependencyIndex) {
      const auto &dependency =
          dependencies[primary.dependency_begin + dependencyIndex];
      if (dependency.kind != dependencyKind)
        continue;
      if (dependencyKind != TALOS_RT_OBSERVER_DEPENDENCY_SIGNAL) {
        affected |= dependency.stable_id == stableID;
        continue;
      }
      affected |= rangesOverlap(dependency.stable_id, dependency.width,
                                stableID, bitWidth);
      if (!affected && clause->registration->snapshotIdentity) {
        __int128 begin = 0, end = 0, publishedBegin = 0, publishedEnd = 0;
        affected =
            physicalRange(dependency.stable_id, dependency.width, begin, end) &&
            physicalRange(stableID, bitWidth, publishedBegin, publishedEnd) &&
            begin < publishedEnd && publishedBegin < end;
      }
    }
    if (affected) {
      // A grouped publication can visit several bits in the same bucket.
      // An unrelated earlier bit must not suppress this clause's own event.
      clause->lastExaminedSequence = sequence;
      candidates.push_back(
          {clause->registration->ownerLogicalToken, clause->clauseIndex});
    }
  };
  auto visitBucket = [&](int64_t page) {
    SignalSubscriptionBucketKey key{kind, objectID, page};
    auto bucket = feature->subscriptionBuckets.find(key);
    if (bucket == feature->subscriptionBuckets.end())
      return true;
    for (const ExactEventBucketEntry &entry : bucket->second) {
      considerClause(entry.clause);
    }
    return true;
  };
  TALOS_RT_TRY {
    if (dependencyKind == TALOS_RT_OBSERVER_DEPENDENCY_MANAGED) {
      for (const auto &[owner, registration] : feature->registrations) {
        (void)owner;
        if (!registration)
          continue;
        for (const auto &clause : registration->clauses)
          considerClause(clause.get());
      }
    } else {
      __int128 pageCount = static_cast<__int128>(lastPage) - firstPage + 1;
      if (pageCount <= kMaximumIndexedSignalPages) {
        if (!visitBucket(kWideSignalSubscriptionPage))
          return false;
        for (int64_t page = firstPage;; ++page) {
          if (!visitBucket(page))
            return false;
          if (page == lastPage)
            break;
        }
      } else {
        std::vector<int64_t> pages;
        for (const auto &[key, bucket] : feature->subscriptionBuckets) {
          (void)bucket;
          if (key.kind == kind && key.id == objectID)
            pages.push_back(key.page);
        }
        for (int64_t page : pages)
          if (!visitBucket(page))
            return false;
      }
    }
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
    return false;
  }

  auto evaluateObserver =
      [&](ExactEventRegistration &registration, uint32_t observerIndex,
          std::vector<uint64_t> &value, std::vector<uint64_t> &unknown,
          uint32_t &resultWidth) -> bool {
    auto *plan = reinterpret_cast<talos_rt_computed_wait_record_v1 *>(
        registration.eventPlan.data());
    auto *observers = computedWaitSpan<talos_rt_computed_observer_v1>(
        plan, plan->observers_offset, plan->observer_count);
    auto *captures = computedWaitSpan<talos_rt_computed_capture_v1>(
        plan, plan->captures_offset, plan->capture_count);
    if (!observers || !captures || observerIndex >= plan->observer_count)
      return false;
    const talos_rt_computed_observer_v1 binding = observers[observerIndex];
    const talos_rt_execution_descriptor_v1 *execution = context->execution;
    uint64_t token = registration.ownerLogicalToken;
    if (registration.native) {
      token &= ~kNativeLogicalProcessTag;
      ScheduledProcess *process = findScheduledProcess(context, token);
      execution = process && process->instance && process->instance->descriptor
                      ? process->instance->descriptor->execution
                      : nullptr;
    }
    const talos_rt_observer_descriptor_v1 *descriptor =
        findObserverDescriptor(execution, binding.code_unit_id);
    if (!descriptor || binding.capture_begin > plan->capture_count ||
        binding.capture_count > plan->capture_count - binding.capture_begin)
      return false;
    resultWidth = descriptor->result_width;
    uint32_t limbs = static_cast<uint32_t>((uint64_t{resultWidth} + 63) / 64);
    if (limbs == 0)
      return false;
    std::vector<talos_rt_computed_capture_v1> copiedCaptures;
    TALOS_RT_TRY {
      copiedCaptures.assign(captures + binding.capture_begin,
                            captures + binding.capture_begin +
                                binding.capture_count);
      value.assign(limbs, 0);
      unknown.assign(limbs, 0);
    }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return false;
    }
    TALOS_RT_CATCH(const std::length_error &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return false;
    }
    return registration.native
               ? talos_rt_evaluate_native_bound_observer_unlocked(
                     context, token, binding.code_unit_id,
                     copiedCaptures.data(), copiedCaptures.size(), value.data(),
                     unknown.data(), limbs)
               : talos_rt_evaluate_design_bound_observer_unlocked(
                     context, token, binding.code_unit_id,
                     copiedCaptures.data(), copiedCaptures.size(), value.data(),
                     unknown.data(), limbs);
  };

  for (const Candidate &candidate : candidates) {
    // Evaluating a compiled observer can cross a callback boundary that
    // temporarily releases the context mutex. Reentrant code may terminate an
    // owner and erase its registration, so re-resolve by stable owner token
    // and copy every field needed by the evaluator before calling it.
    ExactEventFeatureState *currentFeature = context->exactEvents.get();
    if (!currentFeature)
      break;
    auto found =
        currentFeature->registrations.find(candidate.ownerLogicalToken);
    if (found == currentFeature->registrations.end() || !found->second)
      continue;
    ExactEventRegistration &registrationBeforeEvaluation = *found->second;
    auto *plan = reinterpret_cast<talos_rt_computed_wait_record_v1 *>(
        registrationBeforeEvaluation.eventPlan.data());
    auto *clauses = computedWaitSpan<talos_rt_computed_clause_v1>(
        plan, plan->clauses_offset, plan->clause_count);
    auto *observers = computedWaitSpan<talos_rt_computed_observer_v1>(
        plan, plan->observers_offset, plan->observer_count);
    if (!clauses || !observers || candidate.clauseIndex >= plan->clause_count)
      return false;
    talos_rt_computed_clause_v1 clause = clauses[candidate.clauseIndex];
    uint32_t resultWidth = 0;
    std::vector<uint64_t> value;
    std::vector<uint64_t> unknown;
    ClockConditionPublicationOverlay overlay(context, sample);
    if (!evaluateObserver(registrationBeforeEvaluation, clause.primary_observer,
                          value, unknown, resultWidth))
      return false;

    // Observer evaluation can release the context lock. Re-resolve the
    // registration before reading or updating its retained previous result.
    currentFeature = context->exactEvents.get();
    if (!currentFeature)
      break;
    found = currentFeature->registrations.find(candidate.ownerLogicalToken);
    if (found == currentFeature->registrations.end() || !found->second)
      continue;
    ExactEventRegistration &current = *found->second;
    plan = reinterpret_cast<talos_rt_computed_wait_record_v1 *>(
        current.eventPlan.data());
    clauses = computedWaitSpan<talos_rt_computed_clause_v1>(
        plan, plan->clauses_offset, plan->clause_count);
    observers = computedWaitSpan<talos_rt_computed_observer_v1>(
        plan, plan->observers_offset, plan->observer_count);
    if (!clauses || !observers || candidate.clauseIndex >= plan->clause_count)
      return false;
    clause = clauses[candidate.clauseIndex];
    const auto &primary = observers[clause.primary_observer];
    uint32_t limbs = static_cast<uint32_t>((uint64_t{resultWidth} + 63) / 64);
    auto *previousValue = reinterpret_cast<uint64_t *>(
        reinterpret_cast<uint8_t *>(plan) + primary.previous_offset);
    auto *previousUnknown = previousValue + limbs;
    bool changed = false;
    for (uint32_t limb = 0; limb != limbs; ++limb)
      changed |= previousValue[limb] != value[limb] ||
                 previousUnknown[limb] != unknown[limb];
    uint32_t observedEdges = transitionEdges(
        (previousValue[0] & 1) != 0, (previousUnknown[0] & 1) != 0,
        (value[0] & 1) != 0, (unknown[0] & 1) != 0);
    for (uint32_t limb = 0; limb != limbs; ++limb) {
      previousValue[limb] = value[limb];
      previousUnknown[limb] = unknown[limb];
    }
    bool occurrence = clause.edge == TALOS_RT_WAIT_EDGE_CHANGE
                          ? changed
                          : signalEdgeMatches(clause.edge, observedEdges);
    if (!occurrence)
      continue;
    if (clause.condition_observer != TALOS_RT_OBSERVER_CONDITION_NONE) {
      // IEEE 1800-2023 9.4.2.3 evaluates iff only at the primary event
      // instant. The publication overlay retains the just-published value
      // even when generated native storage already contains later stores.
      if (!evaluateObserver(current, clause.condition_observer, value, unknown,
                            resultWidth))
        return false;
      currentFeature = context->exactEvents.get();
      if (!currentFeature)
        break;
      found = currentFeature->registrations.find(candidate.ownerLogicalToken);
      if (found == currentFeature->registrations.end() || !found->second)
        continue;
      if (value.empty() || unknown.empty() || (unknown[0] & 1) != 0 ||
          (value[0] & 1) == 0)
        continue;
    }
    ExactEventRegistration &registration = *found->second;
    if (registration.snapshotIdentity) {
      auto owner = std::find_if(
          snapshotOwners.begin(), snapshotOwners.end(), [&](const auto &entry) {
            return entry.ownerLogicalToken == candidate.ownerLogicalToken &&
                   entry.identity == registration.snapshotIdentity;
          });
      if (owner != snapshotOwners.end())
        owner->mask |= uint64_t{1} << candidate.clauseIndex;
      else {
        TALOS_RT_TRY {
          snapshotOwners.push_back({candidate.ownerLogicalToken,
                                    uint64_t{1} << candidate.clauseIndex,
                                    registration.snapshotIdentity});
        }
        TALOS_RT_CATCH(const std::bad_alloc &) {
          context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
          return false;
        }
      }
      registration.lastSampledSequence = sequence;
      continue;
    }
    if (registration.lastSampledSequence == sequence)
      continue;
    registration.lastSampledSequence = sequence;
    if (registration.strobe) {
      // IEEE 1800-2023 19.3 retains only one automatic sample per time slot
      // when type_option.strobe is set. The event iff was evaluated above at
      // the event instant; sample expressions and enabled state are observed
      // later, when the scheduler enters the Postponed region.
      if (registration.lastStrobeTimeValid &&
          registration.lastStrobeTime == context->schedulerTime)
        continue;
      registration.lastStrobeTime = context->schedulerTime;
      registration.lastStrobeTimeValid = true;
      if (currentFeature->pendingStrobeCount == UINT64_MAX) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return false;
      }
      registration.strobePending = true;
      ++currentFeature->pendingStrobeCount;
      continue;
    }
    TALOS_RT_TRY { sampleOwners.push_back(registration.ownerLogicalToken); }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return false;
    }
    TALOS_RT_CATCH(const std::length_error &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return false;
    }
  }

  // IEEE 1801-2018 6.50: snapshot all qualifying data at the event instant,
  // before a destination write or a user coverage callback can change it.
  // These pure callbacks return only packed data; explicit writes occur at
  // the caller's complete-publication flush boundary, outside every overlay.
  if (!snapshotOwners.empty()) {
    if (context->exactEvents->collectingSnapshotNotifications) {
      TALOS_RT_TRY {
        auto &pending = context->exactEvents->snapshotOccurrences;
        for (auto &occurrence : snapshotOwners) {
          auto found = std::find_if(
              pending.begin(), pending.end(), [&](const auto &entry) {
                return entry.ownerLogicalToken ==
                           occurrence.ownerLogicalToken &&
                       entry.identity == occurrence.identity;
              });
          if (found == pending.end())
            pending.push_back(std::move(occurrence));
          else
            found->mask |= occurrence.mask;
        }
      }
      TALOS_RT_CATCH(const std::bad_alloc &) {
        context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
        return false;
      }
    } else if (!captureEventSnapshotsUnlocked(context, snapshotOwners,
                                              sample)) {
      return false;
    }
  }

  // Complete the event-instant phase for every affected clause before any
  // user sample evaluator runs. This ensures an `or` event commits every
  // primary's retained result even when the first matching clause coalesces
  // the registration's sample. Sampler-triggered publications may now execute
  // recursively because all history for this publication is stable.
  context->exactEventEvaluationDepth = 0;
  for (uint64_t ownerLogicalToken : sampleOwners) {
    ExactEventFeatureState *currentFeature = context->exactEvents.get();
    if (!currentFeature)
      break;
    auto found = currentFeature->registrations.find(ownerLogicalToken);
    if (found == currentFeature->registrations.end() || !found->second)
      continue;
    ExactEventRegistration &registration = *found->second;
    uint32_t enabled = 0;
    talos_rt_status status = talos_rt_v1_covergroup_sample_enabled(
        context, registration.covergroupHandle, &enabled);
    if (status != TALOS_RT_OK) {
      context->schedulerStatus = status;
      return false;
    }
    if (!enabled)
      continue;
    const bool native = registration.native;
    const uint64_t sampleOwnerToken = registration.ownerLogicalToken;
    const uint64_t observerCodeUnitID = registration.observerCodeUnitID;
    std::vector<talos_rt_computed_capture_v1> captures;
    TALOS_RT_TRY { captures = registration.captures; }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return false;
    }
    TALOS_RT_CATCH(const std::length_error &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return false;
    }
    uint64_t sampleValue = 0;
    uint64_t sampleUnknown = 0;
    uint64_t token = native ? sampleOwnerToken & ~kNativeLogicalProcessTag
                            : sampleOwnerToken;
    ClockConditionPublicationOverlay overlay(context, sample);
    bool evaluated =
        native ? talos_rt_evaluate_native_clock_condition_unlocked(
                     context, token, observerCodeUnitID, captures.data(),
                     captures.size(), sampleValue, sampleUnknown)
               : talos_rt_evaluate_design_clock_condition_unlocked(
                     context, token, observerCodeUnitID, captures.data(),
                     captures.size(), sampleValue, sampleUnknown);
    if (!evaluated)
      return false;
    if (sampleUnknown != 0 || sampleValue != 1) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return false;
    }
  }
  return true;
}

bool evaluateExactEventsUnlocked(talos_rt_context *context, uint64_t sequence,
                                 uint32_t dependencyKind, uint32_t kind,
                                 uint32_t objectID, int64_t firstPage,
                                 int64_t lastPage, uint64_t stableID,
                                 uint64_t bitWidth,
                                 const ClockConditionPublicationView *sample) {
  if (!context)
    return false;
  ExactEventFeatureState *feature = context->exactEvents.get();
  if (!feature)
    return true;
  if (feature->collectingSnapshotNotifications) {
    // Atomic packed/alias publications retain one exact-event identity even
    // when their low-level signal routing visits multiple ranges or bits.
    // Ordinary covergroup `or` events must sample only once as well.
    if (!feature->groupedExactSequence)
      feature->groupedExactSequence = sequence;
    sequence = feature->groupedExactSequence;
  }
  if ((feature->flushingSnapshots || feature->collectingSnapshotNotifications ||
       !feature->snapshots.empty()) &&
      context->observerDepth != 0) {
    // Explicit snapshot transactions admit read-only notification callbacks.
    // A foreign callback that publishes recursively cannot interleave a new
    // event ahead of the remaining atomic target notifications.
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return false;
  }
  if (context->exactEventEvaluationDepth != 0) {
    // Compiler-generated primary and iff observers are required to be
    // read-only, so they cannot publish recursively. Reject a malformed or
    // foreign descriptor that violates that contract instead of deferring its
    // iff evaluation past the IEEE 1800 event instant.
    context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
    return false;
  }

  struct EvaluationGuard {
    talos_rt_context *context;
    ~EvaluationGuard() {
      context->exactEventEvaluationDepth = 0;
      auto *feature = context->exactEvents.get();
      if (feature && feature->dispatchDepth)
        --feature->dispatchDepth;
      if (feature && !feature->dispatchDepth && !feature->flushingSnapshots &&
          !feature->collectingSnapshotNotifications &&
          feature->registrations.empty() && feature->snapshots.empty())
        context->exactEvents.reset();
    }
  } guard{context};
  ++feature->dispatchDepth;
  context->exactEventEvaluationDepth = 1;
  return evaluateExactEventsNowUnlocked(context, sequence, dependencyKind, kind,
                                        objectID, firstPage, lastPage, stableID,
                                        bitWidth, sample);
}

bool recordClockOccurrenceUnlocked(
    talos_rt_context *context, ClockOccurrenceSubscription &subscription,
    const ClockConditionPublicationView *sample) {
  if (subscription.waiterToken == 0) {
    subscription.clockingOutputSeen = true;
    subscription.lastClockingOutputTime = context->schedulerTime;
    return true;
  }
  bool native = subscription.native;
  uint64_t logicalToken =
      native ? kNativeLogicalProcessTag | subscription.waiterToken
             : subscription.waiterToken;
  if (!context->clockOccurrences) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return false;
  }
  auto found = context->clockOccurrences->waits.find(logicalToken);
  if (found == context->clockOccurrences->waits.end() ||
      subscription.occurrenceBit >= found->second.conditions.size()) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return false;
  }
  ClockOccurrenceWaitState &state = found->second;
  if (!readClockOccurrenceCondition(
          context, state.conditions[subscription.occurrenceBit], sample,
          subscription.waiterToken, native))
    return true;
  ClockOccurrenceWaveKey key{context->schedulerTime,
                             context->schedulerSlotProgress,
                             context->activeExecRegion};
  if (state.hasCurrentKey && !(state.currentKey == key))
    finalizeClockOccurrenceWave(state);
  if (!state.hasCurrentKey) {
    state.currentKey = key;
    state.hasCurrentKey = true;
  }
  uint64_t ordinal = state.occurrenceCounts[subscription.occurrenceBit]++;
  if (ordinal >= std::numeric_limits<size_t>::max()) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  if (state.currentCohorts.size() <= ordinal)
    state.currentCohorts.resize(static_cast<size_t>(ordinal) + 1, 0);
  state.currentCohorts[ordinal] |= uint64_t{1} << subscription.occurrenceBit;

  bool wasTriggered = false;
  if (native) {
    ScheduledProcess *process =
        findScheduledProcess(context, subscription.waiterToken);
    if (!process || !process->instance || !process->started) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return false;
    }
    wasTriggered = process->signalTriggered;
    process->signalTriggered = true;
    if (!wasTriggered)
      context->nativePollCandidates.insert(subscription.waiterToken);
  } else {
    auto indexed =
        context->scheduledDesignTaskIndices.find(subscription.waiterToken);
    if (indexed == context->scheduledDesignTaskIndices.end() ||
        indexed->second >= context->scheduledDesignTasks.size()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return false;
    }
    ScheduledDesignTask &task = context->scheduledDesignTasks[indexed->second];
    if (task.id != subscription.waiterToken || task.terminated ||
        !task.started) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return false;
    }
    wasTriggered = task.signalTriggered;
    task.signalTriggered = true;
    if (!wasTriggered)
      context->designPollCandidates.insert(subscription.waiterToken);
  }
  if (!wasTriggered && context->saif)
    talos_rt_saif_wake_unlocked(
        context,
        subscription.waiterToken |
            (native ? TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG : uint64_t{0}));
  if (!wasTriggered && ++context->schedulerSelectionGeneration == 0)
    context->schedulerSelectionGeneration = 1;
  return true;
}

} // namespace

bool captureEventSnapshotsUnlocked(
    talos_rt_context *context,
    const std::vector<EventSnapshotOccurrence> &occurrences,
    const ClockConditionPublicationView *sample) {
  struct PurePhaseGuard {
    talos_rt_context *context;
    uint32_t previous;
    ~PurePhaseGuard() { context->exactEventEvaluationDepth = previous; }
  } pure{context, context->exactEventEvaluationDepth};
  context->exactEventEvaluationDepth = 1;
  TALOS_RT_TRY {
    ExactEventFeatureState &current = *context->exactEvents;
    // The C API requires a flush between qualifying source publications.
    // Fail closed rather than sample a later restore from an uncommitted
    // earlier save. Nested callbacks cannot supply that boundary.
    if (!current.snapshots.empty()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return false;
    }
    EventSnapshotBatch batch;
    batch.reserve(occurrences.size());
    for (const auto &occurrence : occurrences) {
      uint64_t owner = occurrence.ownerLogicalToken;
      auto found = current.registrations.find(owner);
      if (found == current.registrations.end() ||
          found->second->snapshotIdentity != occurrence.identity)
        continue;
      EventSnapshotWork work;
      work.ownerLogicalToken = owner;
      work.identity = found->second->snapshotIdentity;
      work.targets = found->second->snapshotTargets;
      auto captures = found->second->captures;
      uint64_t codeUnit = found->second->observerCodeUnitID;
      bool native = found->second->native;
      uint64_t token = native ? owner & ~kNativeLogicalProcessTag : owner;
      uint64_t width = 0;
      for (const auto &target : work.targets)
        width += target.abi.width;
      uint32_t limbs = static_cast<uint32_t>((width + 63) / 64);
      work.value.assign(limbs, 0);
      work.unknown.assign(limbs, 0);
      bool evaluated = false;
      {
        struct SamplingGuard {
          ExactEventFeatureState &feature;
          ~SamplingGuard() {
            feature.samplingSnapshot = false;
            feature.snapshotMask = 0;
          }
        } guard{current};
        current.samplingSnapshot = true;
        current.snapshotMask = occurrence.mask;
        ClockConditionPublicationOverlay overlay(context, sample);
        evaluated = native ? talos_rt_evaluate_native_bound_observer_unlocked(
                                 context, token, codeUnit, captures.data(),
                                 captures.size(), work.value.data(),
                                 work.unknown.data(), limbs)
                           : talos_rt_evaluate_design_bound_observer_unlocked(
                                 context, token, codeUnit, captures.data(),
                                 captures.size(), work.value.data(),
                                 work.unknown.data(), limbs);
      }
      if (!evaluated) {
        if (context->schedulerStatus == TALOS_RT_OK)
          context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
        return false;
      }
      found = current.registrations.find(owner);
      if (found != current.registrations.end() &&
          found->second->snapshotIdentity == work.identity)
        batch.push_back(std::move(work));
    }
    if (!batch.empty())
      current.snapshots.push_back(std::move(batch));
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
    return false;
  }
  TALOS_RT_CATCH(const std::length_error &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  return true;
}

bool talos_rt_evaluate_covergroup_managed_clock_events_unlocked(
    talos_rt_context *context, uint64_t token) {
  if (!context || !context->exactEvents)
    return context != nullptr;
  if (token == 0 || context->nextSchedulerSequence == 0) {
    context->schedulerStatus =
        token == 0 ? TALOS_RT_INVALID_HANDLE : TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  uint64_t sequence = context->nextSchedulerSequence++;
  if (context->signalDiagnosticsEnabled)
    ++context->signalDiagnostics.publications;
  return evaluateExactEventsUnlocked(context, sequence,
                                     TALOS_RT_OBSERVER_DEPENDENCY_MANAGED, 0, 0,
                                     0, 0, token, 1, nullptr);
}

bool talos_rt_covergroup_strobes_pending_unlocked(
    const talos_rt_context *context) {
  if (!context || !context->exactEvents)
    return false;
  return context->exactEvents->pendingStrobeCount != 0;
}

talos_rt_status
talos_rt_drain_covergroup_strobes_unlocked(talos_rt_context *context) {
  if (!context || !context->exactEvents)
    return context ? TALOS_RT_OK : TALOS_RT_INVALID_ARGUMENT;

  std::vector<uint64_t> owners;
  TALOS_RT_TRY {
    owners.reserve(context->exactEvents->registrations.size());
    for (const auto &[owner, registration] :
         context->exactEvents->registrations)
      if (registration && registration->strobePending)
        owners.push_back(owner);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
    return context->schedulerStatus;
  }
  TALOS_RT_CATCH(const std::length_error &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return context->schedulerStatus;
  }

  struct PostponedRegionGuard {
    talos_rt_context *context;
    uint32_t home;
    uint32_t exec;

    explicit PostponedRegionGuard(talos_rt_context *context)
        : context(context), home(context->activeHomeRegion),
          exec(context->activeExecRegion) {
      context->activeHomeRegion = TALOS_RT_REGION_POSTPONED;
      context->activeExecRegion = TALOS_RT_REGION_POSTPONED;
    }
    ~PostponedRegionGuard() {
      context->activeHomeRegion = home;
      context->activeExecRegion = exec;
    }
  } postponedRegion(context);

  for (uint64_t owner : owners) {
    // The observer evaluator releases the recursive context mutex around a
    // native callback. Re-resolve every candidate by stable owner token and
    // copy its evaluator state before crossing that boundary, just as the
    // event-instant path does.
    ExactEventFeatureState *feature = context->exactEvents.get();
    if (!feature)
      break;
    auto found = feature->registrations.find(owner);
    if (found == feature->registrations.end() || !found->second ||
        !found->second->strobePending)
      continue;
    ExactEventRegistration &registration = *found->second;
    registration.strobePending = false;
    if (feature->pendingStrobeCount == 0) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return context->schedulerStatus;
    }
    --feature->pendingStrobeCount;

    uint32_t enabled = 0;
    talos_rt_status status = talos_rt_v1_covergroup_sample_enabled(
        context, registration.covergroupHandle, &enabled);
    if (status != TALOS_RT_OK) {
      context->schedulerStatus = status;
      return status;
    }
    if (!enabled)
      continue;

    const bool native = registration.native;
    const uint64_t observerCodeUnitID = registration.observerCodeUnitID;
    const uint64_t token = native ? owner & ~kNativeLogicalProcessTag : owner;
    std::vector<talos_rt_computed_capture_v1> captures;
    TALOS_RT_TRY { captures = registration.captures; }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return context->schedulerStatus;
    }
    TALOS_RT_CATCH(const std::length_error &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return context->schedulerStatus;
    }
    uint64_t value = 0;
    uint64_t unknown = 0;
    bool evaluated =
        native ? talos_rt_evaluate_native_clock_condition_unlocked(
                     context, token, observerCodeUnitID, captures.data(),
                     captures.size(), value, unknown)
               : talos_rt_evaluate_design_clock_condition_unlocked(
                     context, token, observerCodeUnitID, captures.data(),
                     captures.size(), value, unknown);
    if (!evaluated) {
      if (context->schedulerStatus == TALOS_RT_OK)
        context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return context->schedulerStatus;
    }
    if (unknown != 0 || value != 1) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return context->schedulerStatus;
    }
  }
  return TALOS_RT_OK;
}

bool talos_rt_read_clock_condition_publication_bit_unlocked(
    const talos_rt_context *context, uint64_t stableID, uint64_t bit,
    bool &value, bool &unknown) {
  if (!context || !context->observerForcesCanonicalPlane ||
      bit > uint64_t{INT64_MAX})
    return false;
  talos_rt_stable_handle_v1 loaded;
  // A partially out-of-range view may start below zero and still overlap a
  // valid publication. Match the selected bit, not just the view's base.
  if (!talos_rt_stable_handle_decode(stableID, &loaded))
    return false;
  auto rootBounds = [&](const talos_rt_stable_handle_v1 &handle,
                        __int128 &begin, __int128 &end) {
    begin = 0;
    if (handle.kind == TALOS_RT_STABLE_HANDLE_STATIC) {
      const auto *state = findNativeStaticState(context, handle.id);
      if (!state)
        return false;
      begin = state->bitOffset;
      end = begin + state->bitWidth;
      return true;
    }
    if (handle.kind != TALOS_RT_STABLE_HANDLE_GLOBAL)
      return false;
    end = context->execution ? context->execution->state_bit_count
                             : context->stateValue.size() * uint64_t{64};
    return true;
  };
  for (const ClockConditionPublicationView *publication =
           context->conditionPublication;
       publication; publication = publication->previous) {
    if (!publication->newValue || publication->bitWidth == 0)
      continue;
    talos_rt_stable_handle_v1 published;
    if (!talos_rt_stable_handle_decode(publication->stableID, &published))
      continue;
    if (published.kind != TALOS_RT_STABLE_HANDLE_GLOBAL &&
        published.kind != TALOS_RT_STABLE_HANDLE_STATIC)
      continue;
    bool sameObject = published.kind == loaded.kind &&
                      (published.kind == TALOS_RT_STABLE_HANDLE_GLOBAL ||
                       published.id == loaded.id);
    __int128 relative = static_cast<__int128>(loaded.offset) + bit -
                        static_cast<__int128>(published.offset);
    if (sameObject &&
        (loaded.kind == TALOS_RT_STABLE_HANDLE_STATIC || context->execution)) {
      __int128 begin = 0, end = 0;
      __int128 coordinate = static_cast<__int128>(loaded.offset) + bit;
      if (!rootBounds(loaded, begin, end) || coordinate < 0 ||
          coordinate >= end - begin)
        continue;
    }
    if (!sameObject || published.offset < 0) {
      // IEEE 1801-2018 6.50: the newest frozen payload shadows enclosing
      // values through GLOBAL/STATIC aliases. Clip partial writes to the
      // declaring root, retaining older views of unrelated bits.
      __int128 loadedBegin = 0, loadedEnd = 0, publishedBegin = 0,
               publishedEnd = 0;
      if (!rootBounds(loaded, loadedBegin, loadedEnd) ||
          !rootBounds(published, publishedBegin, publishedEnd))
        continue;
      __int128 coordinate = loadedBegin + loaded.offset + bit;
      __int128 start = publishedBegin + published.offset;
      if (coordinate < loadedBegin || coordinate >= loadedEnd ||
          coordinate < std::max(start, publishedBegin) ||
          coordinate >= std::min(start + publication->bitWidth, publishedEnd))
        continue;
      relative = coordinate - start;
    }
    if (relative < 0 || relative >= publication->bitWidth ||
        static_cast<uint64_t>(relative) >
            UINT64_MAX - publication->planeBitOffset)
      continue;
    uint64_t source =
        publication->planeBitOffset + static_cast<uint64_t>(relative);
    value = byteBit(publication->newValue, source);
    unknown =
        publication->newUnknown && byteBit(publication->newUnknown, source);
    return true;
  }
  return false;
}

void wakeMonitorProcessUnlocked(talos_rt_context *context,
                                uint64_t logicalToken) {
  if (!logicalToken)
    return;
  if ((logicalToken & kNativeLogicalProcessTag) != 0) {
    uint64_t token = logicalToken & ~kNativeLogicalProcessTag;
    if (ScheduledProcess *process = findScheduledProcess(context, token);
        process && process->instance) {
      talos_rt_unregister_signal_wait_unlocked(
          context, process->signalSubscriptions, process->token, false);
      process->suspendKind = TALOS_RT_SUSPEND_NONE;
      process->signalTriggered = false;
      process->urgent = false;
      process->queuedRegion = TALOS_RT_REGION_POSTPONED;
      context->nativePollCandidates.insert(token);
      if (++context->schedulerSelectionGeneration == 0)
        context->schedulerSelectionGeneration = 1;
    }
    return;
  }
  for (ScheduledDesignTask &task : context->scheduledDesignTasks) {
    if (task.id != logicalToken || task.terminated)
      continue;
    talos_rt_unregister_signal_wait_unlocked(context, task.signalSubscriptions,
                                             task.id, true);
    task.suspendKind = TALOS_RT_SUSPEND_NONE;
    task.signalTriggered = false;
    task.urgent = false;
    task.queuedRegion = TALOS_RT_REGION_POSTPONED;
    context->designPollCandidates.insert(logicalToken);
    if (++context->schedulerSelectionGeneration == 0)
      context->schedulerSelectionGeneration = 1;
    return;
  }
}

template <typename Matches, typename ClockMatches>
static bool
publishSignalOccurrenceUnlocked(talos_rt_context *context, uint64_t stableID,
                                uint64_t bitWidth, Matches &&matches,
                                ClockMatches &&clockMatches,
                                const ClockConditionPublicationView *sample,
                                uint64_t *outSequence = nullptr) {
  if (context->nextSchedulerSequence == 0) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  uint64_t sequence = context->nextSchedulerSequence++;
  if (outSequence)
    *outSequence = sequence;
  if (context->signalDiagnosticsEnabled)
    ++context->signalDiagnostics.publications;
  // A direct native wait is polled by the generated schedule only while that
  // schedule owns execution.  During a transient fine-scheduler handoff the
  // same subscription must seed the runtime candidate set instead; otherwise
  // a force/assign that survives the current slot can strand every subsequent
  // edge-triggered actor while the fine scheduler advances time.
  bool fullyStaticAOT = !context->nativeScheduleStopAtCleanBoundary &&
                        context->nativeSchedulePlan &&
                        !context->nativeScheduleDeoptimized &&
                        (context->nativeSchedulePlan->flags &
                         TALOS_RT_NATIVE_SCHEDULE_FULLY_STATIC) != 0;

  uint32_t kind = 0;
  uint32_t objectID = 0;
  int64_t firstPage = 0;
  int64_t lastPage = 0;
  if (!signalSubscriptionBucketRange(stableID, bitWidth, kind, objectID,
                                     firstPage, lastPage)) {
    context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
    return false;
  }
  auto visitEntries = [&](const std::vector<SignalSubscriptionBucketEntry>
                              &bucket) {
    for (const SignalSubscriptionBucketEntry &entry : bucket) {
      SignalSubscription *subscription = entry.subscription;
      if (!subscription || subscription->lastExaminedSequence == sequence)
        continue;
      if (subscription->latch && !subscription->latch->armed)
        continue;
      subscription->lastExaminedSequence = sequence;
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.subscribersExamined;
      bool overlaps = false;
      if (fullyStaticAOT &&
          subscription->target == SignalSubscription::NativeDirectWait) {
        int64_t publishedOffset = static_cast<int32_t>(stableID);
        int64_t subscribedOffset = static_cast<int32_t>(subscription->stableID);
        overlaps =
            static_cast<__int128>(publishedOffset) + bitWidth >
                subscribedOffset &&
            static_cast<__int128>(subscribedOffset) + subscription->bitWidth >
                publishedOffset;
      } else {
        overlaps = rangesOverlap(subscription->stableID, subscription->bitWidth,
                                 stableID, bitWidth);
      }
      if (!overlaps)
        continue;
      if (subscription->suppressActiveSelf && subscription->waiterToken != 0) {
        uint64_t logicalToken =
            subscription->target == SignalSubscription::NativeDirectWait
                ? kNativeLogicalProcessTag | subscription->waiterToken
                : subscription->waiterToken;
        if (context->activeLogicalProcessToken == logicalToken)
          continue;
      }
      if (!matches(*subscription))
        continue;
      if (subscription->target == SignalSubscription::NativeDirectWait &&
          subscription->latch && !subscription->latch->triggered &&
          context->nativeSchedulePlan &&
          (context->nativeSchedulePlan->flags &
           TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL) &&
          canUseStaticAOTFanout(context)) {
        // IEEE 1800-2023 9.4.2: deliver this publication to both generated
        // and runtime waiters. Route only a certified native continuation
        // into generated ingress; leave every other subscription below.
        ScheduledProcess *scheduled =
            findScheduledProcess(context, subscription->waiterToken);
        if (!subscription->outsideStaticFanout &&
            context->nativePeriodicPublicationHandle == stableID && scheduled &&
            scheduled->instance &&
            scheduled->aotActorSlot <
                context->nativePeriodicAliasContinuations.size() &&
            context->nativePeriodicAliasContinuations[scheduled
                                                          ->aotActorSlot] ==
                scheduled->instance->continuation)
          continue;
        uint32_t node =
            scheduled && scheduled->instance
                ? findNativeAOTNodeUnlocked(context, scheduled->aotActorSlot,
                                            scheduled->instance->continuation)
                : UINT32_MAX;
        if (node < context->nativeScheduleNodeIngress.size()) {
          uint64_t index = context->nativeScheduleNodeIngress[node];
          if (index < context->nativeScheduleFanoutEntryCount &&
              (context->nativeScheduleFanoutEntries[index].reserved &
               TALOS_RT_FANOUT_ROUTE_MASK) == TALOS_RT_FANOUT_DIRECT) {
            const auto &entry = context->nativeScheduleFanoutEntries[index];
            const auto &kernel =
                context->nativeSchedulePlan->clock_kernels[entry.kernel];
            if (context->saif)
              talos_rt_saif_wake_actor_unlocked(context, entry.actor_slot);
            talos::runtime::publishClockKernelReady(kernel, entry.merged_bit);
            context->nativeScheduleClockIngressPending = true;
            continue;
          }
        }
      }
      if (subscription->target == SignalSubscription::NativeDirectWait ||
          subscription->target == SignalSubscription::DesignDirectWait) {
        if (!subscription->latch || subscription->latch->triggered)
          continue;
        if (context->saif)
          talos_rt_saif_wake_unlocked(
              context,
              subscription->waiterToken |
                  (subscription->target == SignalSubscription::NativeDirectWait
                       ? TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG
                       : uint64_t{0}));
        subscription->latch->triggered = true;
        bool staticallyPolledNative =
            fullyStaticAOT &&
            subscription->target == SignalSubscription::NativeDirectWait &&
            !subscription->outsideStaticFanout;
        if (staticallyPolledNative) {
          ScheduledProcess *scheduled =
              findScheduledProcess(context, subscription->waiterToken);
          if (!scheduled || scheduled->aotActorSlot == UINT32_MAX ||
              !markNativeAOTActorReadyUnlocked(context,
                                               scheduled->aotActorSlot)) {
            context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
            return false;
          }
        }
        bool recordedNativePublication = false;
        if (!staticallyPolledNative && subscription->waiterToken != 0) {
          auto &candidates =
              subscription->target == SignalSubscription::NativeDirectWait
                  ? context->nativePollCandidates
                  : context->designPollCandidates;
          TALOS_RT_TRY {
            bool inserted = candidates.insert(subscription->waiterToken).second;
            if (subscription->target == SignalSubscription::NativeDirectWait) {
              talos_rt_record_native_ready_publication_unlocked(
                  context, subscription->waiterToken, inserted);
              recordedNativePublication = true;
            }
          }
          TALOS_RT_CATCH(const std::bad_alloc &) {
            context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
            return false;
          }
        }
        if (!staticallyPolledNative && !recordedNativePublication &&
            ++context->schedulerSelectionGeneration == 0)
          context->schedulerSelectionGeneration = 1;
        continue;
      }
      if (!subscription->latch) {
        // Callback subscriptions own no SV wait latch. Use the existing null
        // exit for their cold capture path; ordinary direct/computed waiters
        // reach no new VPI target check.
        if (subscription->target == SignalSubscription::VPIValueChange &&
            !talos_rt_vpi_capture_change_unlocked(context,
                                                  subscription->waiterToken))
          return false;
        continue;
      }
      if (subscription->latch->affected)
        continue;
      TALOS_RT_TRY {
        auto &pending =
            subscription->target == SignalSubscription::NativeComputedWait
                ? context->pendingNativeComputedWaiters
                : context->pendingDesignComputedWaiters;
        pending.push_back(subscription->waiterToken);
        subscription->latch->affected = true;
      }
      TALOS_RT_CATCH(const std::bad_alloc &) {
        context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
        return false;
      }
    }
    return true;
  };
  auto visitBucket = [&](int64_t page) {
    auto bucket = context->signalSubscriptionBuckets.find(
        SignalSubscriptionBucketKey{kind, objectID, page});
    return bucket == context->signalSubscriptionBuckets.end() ||
           visitEntries(bucket->second);
  };
  __int128 pageCount = static_cast<__int128>(lastPage) - firstPage + 1;
  // LRM 9.4.2: skip only the ordinary subscription lookup when the complete
  // object is unwatched. Clock-occurrence and covergroup indexes below are
  // independent and still observe the publication, including its sequence.
  bool objectWatched =
      context
          ->signalSubscriptionObjectFilter[signalSubscriptionObjectFilterIndex(
              kind, objectID)] != 0;
  // A static object's pages come from its index, in page order with the wide
  // page first, as the probes below would visit them.
  const auto *staticPages =
      objectWatched
          ? talos_rt_static_signal_bucket_pages(context, kind, objectID)
          : nullptr;
  // Nothing visited registers or removes a subscription, so the index does
  // not change during the walk.
  if (staticPages) {
    const auto &pages = *staticPages;
    size_t index = 0;
    if (!pages.empty() && pages.front().page == kWideSignalSubscriptionPage) {
      if (!visitEntries(*pages.front().bucket))
        return false;
      index = 1;
    }
    // A short page list is walked from its start; a long one from the first
    // page at or after firstPage.
    if (pages.size() - index > 8)
      index = static_cast<size_t>(
          std::lower_bound(
              pages.begin() + static_cast<ptrdiff_t>(index), pages.end(),
              firstPage,
              [](const talos_rt_context::StaticSignalBucketPage &entry,
                 int64_t page) { return entry.page < page; }) -
          pages.begin());
    for (; index < pages.size(); ++index) {
      int64_t page = pages[index].page;
      if (page > lastPage)
        break;
      if (page >= firstPage && !visitEntries(*pages[index].bucket))
        return false;
    }
  } else if (objectWatched && pageCount <= kMaximumIndexedSignalPages) {
    if (!visitBucket(kWideSignalSubscriptionPage))
      return false;
    for (int64_t page = firstPage;; ++page) {
      if (!visitBucket(page))
        return false;
      if (page == lastPage)
        break;
    }
  } else if (objectWatched) {
    std::vector<int64_t> pages;
    TALOS_RT_TRY {
      for (const auto &[key, bucket] : context->signalSubscriptionBuckets) {
        (void)bucket;
        if (key.kind == kind && key.id == objectID)
          pages.push_back(key.page);
      }
    }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return false;
    }
    for (int64_t page : pages)
      if (!visitBucket(page))
        return false;
  }

  // Exact multi-clock coordination owns a separate lazy subscription index.
  // Ordinary publication performs only this cold null-pointer gate and keeps
  // its long-standing subscription representation and matching path intact.
  if (!evaluateExactEventsUnlocked(
          context, sequence, TALOS_RT_OBSERVER_DEPENDENCY_SIGNAL, kind,
          objectID, firstPage, lastPage, stableID, bitWidth, sample))
    return false;

  ClockOccurrenceFeatureState *feature = context->clockOccurrences.get();
  if (!feature)
    return true;
  auto visitClockBucket = [&](int64_t page) {
    SignalSubscriptionBucketKey key{kind, objectID, page};
    auto bucket = feature->subscriptionBuckets.find(key);
    if (bucket == feature->subscriptionBuckets.end())
      return true;
    for (const ClockOccurrenceBucketEntry &entry : bucket->second) {
      ClockOccurrenceSubscription *subscription = entry.subscription;
      if (!subscription || subscription->lastExaminedSequence == sequence)
        continue;
      subscription->lastExaminedSequence = sequence;
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.subscribersExamined;
      if (!rangesOverlap(subscription->stableID, subscription->bitWidth,
                         stableID, bitWidth) ||
          !clockMatches(*subscription))
        continue;
      if (!recordClockOccurrenceUnlocked(context, *subscription, sample))
        return false;
    }
    return true;
  };
  if (pageCount <= kMaximumIndexedSignalPages) {
    if (!visitClockBucket(kWideSignalSubscriptionPage))
      return false;
    for (int64_t page = firstPage;; ++page) {
      if (!visitClockBucket(page))
        return false;
      if (page == lastPage)
        break;
    }
  } else {
    std::vector<int64_t> pages;
    TALOS_RT_TRY {
      for (const auto &[key, bucket] : feature->subscriptionBuckets) {
        (void)bucket;
        if (key.kind == kind && key.id == objectID)
          pages.push_back(key.page);
      }
    }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return false;
    }
    for (int64_t page : pages)
      if (!visitClockBucket(page))
        return false;
  }
  return true;
}

bool isCustomClockEdge(uint32_t edge) {
  return (edge & ~TALOS_RT_WAIT_EDGE_TRANSITION_CLASSES) ==
             TALOS_RT_WAIT_EDGE_TRANSITION_MASK &&
         (edge & TALOS_RT_WAIT_EDGE_TRANSITION_CLASSES) != 0;
}

uint32_t clockTransitionClass(bool oldValue, bool oldUnknown, bool newValue,
                              bool newUnknown) {
  if (oldUnknown)
    return newUnknown ? 0 : newValue ? uint32_t{1} << 5 : uint32_t{1} << 4;
  if (!oldValue)
    return newUnknown ? uint32_t{1} << 1 : newValue ? uint32_t{1} << 0 : 0;
  return newUnknown ? uint32_t{1} << 3 : !newValue ? uint32_t{1} << 2 : 0;
}

bool customClockTransitionMatches(
    talos_rt_context *context, ClockOccurrenceSubscription &subscription,
    uint64_t stableID, uint64_t bitWidth, const uint8_t *changed,
    uint64_t edgeBitOffset, const uint8_t *publishedOldValue,
    const uint8_t *publishedOldUnknown, const uint8_t *publishedNewValue,
    const uint8_t *publishedNewUnknown) {
  talos_rt_stable_handle_v1 published;
  talos_rt_stable_handle_v1 subscribed;
  if (!talos_rt_stable_handle_decode(stableID, &published) ||
      !talos_rt_stable_handle_decode(subscription.stableID, &subscribed)) {
    context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
    return false;
  }
  __int128 overlapBegin =
      std::max<__int128>(published.offset, subscribed.offset);
  __int128 overlapEnd = std::min(
      static_cast<__int128>(published.offset) + bitWidth,
      static_cast<__int128>(subscribed.offset) + subscription.bitWidth);
  bool matched = false;
  for (__int128 coordinate = overlapBegin; coordinate < overlapEnd;
       ++coordinate) {
    uint64_t publishedBit =
        static_cast<uint64_t>(coordinate - published.offset);
    if (changed && !byteBit(changed, edgeBitOffset + publishedBit))
      continue;
    uint64_t subscribedBit =
        static_cast<uint64_t>(coordinate - subscribed.offset);
    bool initialized =
        byteBit(subscription.previousInitialized.data(), subscribedBit);
    bool oldValue = false;
    bool oldUnknown = false;
    if (initialized) {
      oldValue = byteBit(subscription.previousValue.data(), subscribedBit);
      oldUnknown = byteBit(subscription.previousUnknown.data(), subscribedBit);
    } else if (publishedOldValue) {
      oldValue = byteBit(publishedOldValue, publishedBit);
      oldUnknown =
          publishedOldUnknown && byteBit(publishedOldUnknown, publishedBit);
    }
    bool newValue = false;
    bool newUnknown = false;
    if (publishedNewValue) {
      newValue = byteBit(publishedNewValue, publishedBit);
      newUnknown =
          publishedNewUnknown && byteBit(publishedNewUnknown, publishedBit);
    } else if (!talos_rt_read_signal_bit_unlocked(
                   context, subscription.stableID, subscribedBit, newValue,
                   newUnknown, /*useSnapshot=*/false)) {
      context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
      return false;
    }
    setByteBit(subscription.previousValue.data(), subscribedBit, newValue);
    setByteBit(subscription.previousUnknown.data(), subscribedBit, newUnknown);
    setByteBit(subscription.previousInitialized.data(), subscribedBit, true);
    // If no prior plane was observable, importing this first published value
    // establishes the snapshot but cannot manufacture an IEEE 31.5 edge.
    if (!initialized && !publishedOldValue)
      continue;
    uint32_t transition =
        clockTransitionClass(oldValue, oldUnknown, newValue, newUnknown);
    matched |= (transition & (subscription.edge &
                              TALOS_RT_WAIT_EDGE_TRANSITION_CLASSES)) != 0;
  }
  // IEEE 1800-2017 31.8 makes all matching bits in one packed publication one
  // vector occurrence. The existing occurrence-bucket visit already coalesces
  // multi-page overlap and repeated publications remain separate cohorts.
  return matched;
}

template <typename Subscription>
static bool signalTransitionBatchMatches(const Subscription &subscription,
                                         uint64_t stableID, uint64_t bitWidth,
                                         const uint8_t *changed,
                                         const uint8_t *posedge,
                                         const uint8_t *negedge,
                                         uint64_t edgeBitOffset, bool direct) {
  int64_t publishedOffset = 0;
  int64_t subscribedOffset = 0;
  if ((stableID & TALOS_RT_STABLE_HANDLE_TAG_MASK) ==
          TALOS_RT_STABLE_HANDLE_STATIC_TAG &&
      (subscription.stableID & TALOS_RT_STABLE_HANDLE_TAG_MASK) ==
          TALOS_RT_STABLE_HANDLE_STATIC_TAG) {
    if ((stableID >> 32) != (subscription.stableID >> 32))
      return false;
    publishedOffset = static_cast<int32_t>(stableID);
    subscribedOffset = static_cast<int32_t>(subscription.stableID);
  } else {
    talos_rt_stable_handle_v1 published;
    talos_rt_stable_handle_v1 subscribed;
    if (!talos_rt_stable_handle_decode(stableID, &published) ||
        !talos_rt_stable_handle_decode(subscription.stableID, &subscribed) ||
        published.kind != subscribed.kind ||
        (published.kind != TALOS_RT_STABLE_HANDLE_GLOBAL &&
         published.id != subscribed.id))
      return false;
    publishedOffset = published.offset;
    subscribedOffset = subscribed.offset;
  }
  __int128 overlapBegin = std::max<__int128>(publishedOffset, subscribedOffset);
  __int128 overlapEnd =
      std::min(static_cast<__int128>(publishedOffset) + bitWidth,
               static_cast<__int128>(subscribedOffset) + subscription.bitWidth);
  if (overlapBegin >= overlapEnd)
    return false;
  uint64_t index =
      edgeBitOffset + static_cast<uint64_t>(overlapBegin - publishedOffset);
  uint64_t width = static_cast<uint64_t>(overlapEnd - overlapBegin);
  if (!direct)
    return anyPackedBits(changed, index, width) ||
           anyPackedBits(posedge, index, width) ||
           anyPackedBits(negedge, index, width);
  switch (subscription.edge) {
  case TALOS_RT_WAIT_EDGE_CHANGE:
    return anyPackedBits(changed, index, width);
  case TALOS_RT_WAIT_EDGE_POSEDGE:
    return anyPackedBits(posedge, index, width);
  case TALOS_RT_WAIT_EDGE_NEGEDGE:
    return anyPackedBits(negedge, index, width);
  case TALOS_RT_WAIT_EDGE_BOTH:
    return anyPackedBits(posedge, index, width) ||
           anyPackedBits(negedge, index, width);
  default:
    return false;
  }
}

static bool publishCovergroupClockTransitionUnlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    const uint8_t *newValue, const uint8_t *newUnknown) {
  (void)changed;
  (void)posedge;
  (void)negedge;
  if (!context->exactEvents)
    return true;
  if (context->nextSchedulerSequence == 0) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return false;
  }
  uint32_t kind = 0;
  uint32_t objectID = 0;
  int64_t firstPage = 0;
  int64_t lastPage = 0;
  if (!signalSubscriptionBucketRange(stableID, bitWidth, kind, objectID,
                                     firstPage, lastPage)) {
    context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
    return false;
  }
  uint64_t sequence = context->nextSchedulerSequence++;
  if (context->signalDiagnosticsEnabled)
    ++context->signalDiagnostics.publications;
  ClockConditionPublicationView sample{stableID, bitWidth, 0, newValue,
                                       newUnknown};
  return evaluateExactEventsUnlocked(
      context, sequence, TALOS_RT_OBSERVER_DEPENDENCY_SIGNAL, kind, objectID,
      firstPage, lastPage, stableID, bitWidth, &sample);
}

bool recordStaticClockingOutputOccurrencesUnlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t edgeBitOffset, uint64_t &sequence) {
  ClockOccurrenceFeatureState *feature = context->clockOccurrences.get();
  if (!feature || feature->clockingOutputs.empty())
    return true;
  uint32_t kind = 0;
  uint32_t objectID = 0;
  int64_t firstPage = 0;
  int64_t lastPage = 0;
  if (!signalSubscriptionBucketRange(stableID, bitWidth, kind, objectID,
                                     firstPage, lastPage)) {
    context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
    return false;
  }
  auto visitBucket = [&](int64_t page) {
    SignalSubscriptionBucketKey key{kind, objectID, page};
    auto bucket = feature->subscriptionBuckets.find(key);
    if (bucket == feature->subscriptionBuckets.end())
      return true;
    for (const ClockOccurrenceBucketEntry &entry : bucket->second) {
      ClockOccurrenceSubscription *subscription = entry.subscription;
      if (!subscription || subscription->waiterToken != 0 ||
          !rangesOverlap(subscription->stableID, subscription->bitWidth,
                         stableID, bitWidth) ||
          !signalTransitionBatchMatches(*subscription, stableID, bitWidth,
                                        changed, posedge, negedge,
                                        edgeBitOffset, true))
        continue;
      if (sequence == 0) {
        if (context->nextSchedulerSequence == 0) {
          context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
          return false;
        }
        sequence = context->nextSchedulerSequence++;
      }
      if (subscription->lastExaminedSequence == sequence)
        continue;
      subscription->lastExaminedSequence = sequence;
      subscription->clockingOutputSeen = true;
      subscription->lastClockingOutputTime = context->schedulerTime;
    }
    return true;
  };
  __int128 pageCount = static_cast<__int128>(lastPage) - firstPage + 1;
  if (pageCount <= kMaximumIndexedSignalPages) {
    if (!visitBucket(kWideSignalSubscriptionPage))
      return false;
    for (int64_t page = firstPage;; ++page) {
      if (!visitBucket(page))
        return false;
      if (page == lastPage)
        break;
    }
    return true;
  }
  for (const auto &[key, bucket] : feature->subscriptionBuckets) {
    (void)bucket;
    if (key.kind == kind && key.id == objectID && !visitBucket(key.page))
      return false;
  }
  return true;
}

static bool staticSignalObjectWatched(const talos_rt_context *context,
                                      uint32_t state) {
  constexpr auto kind = TALOS_RT_STABLE_HANDLE_STATIC;
  if (!context
           ->signalSubscriptionObjectFilter[signalSubscriptionObjectFilterIndex(
               kind, state)])
    return false;
  // Many static descriptors share a counting-filter bucket. The existing
  // per-object page index covers every subscription to an indexed descriptor,
  // including a watch spanning multiple pages (1800-2023 9.4.2).
  const auto *pages = talos_rt_static_signal_bucket_pages(context, kind, state);
  return !pages || !pages->empty();
}

static void
indexPackedNBAChangeRows(PackedNBAChangeMap &map, size_t id,
                         const talos_rt_static_fanout_entry *entries,
                         size_t count, uint64_t width) {
  // Bound installation cost by the number of real fanout rows. Large or
  // mixed-route sources keep the indexed interval walk.
  if (!count || count > 64 || !width || 1 + (width - 1) / 64 > 8 * count)
    return;
  auto &root = map.roots[id];
  uint64_t whole = 0;
  for (size_t i = 0; i < count; ++i) {
    const auto &row = entries[i];
    if (row.edge != TALOS_RT_WAIT_EDGE_CHANGE ||
        (row.reserved & TALOS_RT_FANOUT_ROUTE_MASK) != TALOS_RT_FANOUT_DIRECT ||
        !row.bit_width || row.low_bit >= width ||
        row.bit_width > width - row.low_bit)
      return;
    if (!row.low_bit && row.bit_width == width)
      whole |= uint64_t{1} << i;
  }
  root.all = whole;
  if (whole == packedWidthMask(count))
    return;
  root.firstWord = map.words.size();
  root.words = 1 + (width - 1) / 64;
  for (size_t word = 0; word < root.words; ++word) {
    auto &part = map.words.emplace_back();
    part.firstMask = map.masks.size();
    uint64_t low = word * 64, end = low + std::min<uint64_t>(64, width - low);
    for (size_t i = 0; i < count; ++i) {
      uint64_t row = uint64_t{1} << i;
      if (whole & row)
        continue;
      uint64_t from = std::max(low, entries[i].low_bit);
      uint64_t to = std::min(end, entries[i].low_bit + entries[i].bit_width);
      if (to <= from)
        continue;
      if (from == low && to == end) {
        part.all |= row;
        continue;
      }
      uint64_t bits = packedWidthMask(to - from) << (from - low);
      auto found =
          std::find_if(map.masks.begin() + part.firstMask, map.masks.end(),
                       [&](const auto &m) { return m.bits == bits; });
      if (found == map.masks.end())
        map.masks.push_back({bits, row});
      else
        found->rows |= row;
    }
    part.masks = map.masks.size() - part.firstMask;
  }
  // Consecutive full words can have identical subscribers, for example
  // within a packed array element. A byte comparison reports the entire
  // interval's change with one predicate.
  for (size_t i = root.words - 1; i != 0; --i) {
    auto &previous = map.words[root.firstWord + i - 1];
    const auto &next = map.words[root.firstWord + i];
    if (!previous.masks && !next.masks && previous.all == next.all)
      previous.run = 1 + next.run;
  }
}

void indexScalarNBAFanout(talos_rt_context &context,
                          const talos_rt_static_fanout_entry *entries) {
  const auto &ranges = context.nativeScheduleFanoutRanges;
  context.scalarNBAFanoutMasks.assign(ranges.size(), 0);
  auto changes = std::make_unique<PackedNBAChangeMap>();
  changes->roots.resize(ranges.size());
  for (size_t id = 0; id != ranges.size(); ++id) {
    auto [first, last] = ranges[id];
    if (first == last)
      continue;
    uint32_t kernel = entries[first].kernel;
    uint32_t word = entries[first].merged_bit / 64;
    uint64_t mask = 0;
    for (uint64_t i = first; i != last; ++i) {
      const auto &entry = entries[i];
      if (entry.edge != TALOS_RT_WAIT_EDGE_CHANGE || entry.low_bit ||
          entry.bit_width !=
              context.nativeScheduleStaticStateIndex[id].bitWidth ||
          (entry.reserved & TALOS_RT_FANOUT_ROUTE_MASK) !=
              TALOS_RT_FANOUT_DIRECT ||
          entry.kernel != kernel || entry.merged_bit / 64 != word) {
        mask = 0;
        break;
      }
      mask |= uint64_t{1} << (entry.merged_bit % 64);
    }
    context.scalarNBAFanoutMasks[id] = mask;
    if (!mask)
      indexPackedNBAChangeRows(
          *changes, id, entries + first, last - first,
          context.nativeScheduleStaticStateIndex[id].bitWidth);
  }
  context.packedNBAChanges = std::move(changes);
}

// The first and last possibly overlapping table rows for each source bucket.
// Bound memory by the number of existing waits. An externally supplied table
// need not sort rows by bit position; it retains the original linear walk.
void indexNativeFanoutWindows(talos_rt_context &context,
                              const talos_rt_static_fanout_entry *entries) {
  for (size_t id = 0; id < context.nativeScheduleFanoutRanges.size(); ++id) {
    auto [first, last] = context.nativeScheduleFanoutRanges[id];
    if (last - first < 8 || entries[first].low_bit == entries[last - 1].low_bit)
      continue;
    uint64_t previous = 0, high = 0;
    for (uint64_t i = first; i < last; ++i) {
      const auto &entry = entries[i];
      if (entry.static_state != id || entry.low_bit < previous ||
          !entry.bit_width || entry.bit_width > UINT64_MAX - entry.low_bit) {
        high = 0;
        break;
      }
      high = std::max(high, entry.low_bit + entry.bit_width);
      previous = entry.low_bit;
    }
    if (!high)
      continue;
    uint64_t low = entries[first].low_bit;
    unsigned shift = 0;
    uint64_t budget = 2 * std::min<uint64_t>(512, last - first);
    while (((high - 1) >> shift) - (low >> shift) >= budget)
      ++shift;
    if (context.nativeFanoutWindows.empty())
      context.nativeFanoutWindows.resize(
          context.nativeScheduleFanoutRanges.size());
    auto &source = context.nativeFanoutWindows[id];
    source.shift = shift;
    source.firstBucket = low >> shift;
    uint64_t finalBucket = (high - 1) >> shift;
    source.bounds.reserve(finalBucket - source.firstBucket + 1);
    uint64_t left = first, right = first;
    for (uint64_t bucket = source.firstBucket;; ++bucket) {
      uint64_t start = bucket << shift;
      uint64_t end = bucket == finalBucket ? high : ((bucket + 1) << shift);
      while (left < last &&
             entries[left].low_bit + entries[left].bit_width <= start)
        ++left;
      while (right < last && entries[right].low_bit < end)
        ++right;
      source.bounds.emplace_back(left, right);
      if (bucket == finalBucket)
        break;
    }
  }
}

// Event masks supplied independently at the ABI all participate in this
// bound. The actual edge test still uses the original publication's offset.
static std::pair<uint64_t, uint64_t>
transitionEnvelope(uint64_t width, const uint8_t *changed,
                   const uint8_t *posedge, const uint8_t *negedge) {
  auto word = [&](uint64_t start) {
    uint64_t bits = width - start;
    if (bits >= 64) {
      uint64_t change =
          changed ? loadPackedWord<uint64_t>(changed + start / 8) : 0;
      uint64_t pos =
          posedge ? loadPackedWord<uint64_t>(posedge + start / 8) : 0;
      uint64_t neg =
          negedge ? loadPackedWord<uint64_t>(negedge + start / 8) : 0;
      return change | pos | neg;
    }
    return loadPackedBytes(changed, start, bits) |
           loadPackedBytes(posedge, start, bits) |
           loadPackedBytes(negedge, start, bits);
  };
  uint64_t low = 0, last = (width - 1) & ~uint64_t{63};
  uint64_t firstWord = word(low);
  while (!firstWord && low < last) {
    low += 64;
    firstWord = word(low);
  }
  if (!firstWord)
    return {0, 0};
  uint64_t lastWord = firstWord;
  while (last > low && !(lastWord = word(last)))
    last -= 64;
  if (last == low)
    lastWord = firstWord;
  return {low + __builtin_ctzll(firstWord),
          last + (64 - __builtin_clzll(lastWord))};
}

template <bool UseClockIngress, bool ProjectedClock = false,
          bool UnobservedFanout = false, bool ProjectedSignal = false>
static bool publishStaticAOTSignalTransitionUnlockedImpl(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t *outSequence, bool indexedExternalDeposit) {
  if (outSequence)
    *outSequence = 0;
  if (!UnobservedFanout &&
      !(indexedExternalDeposit ? canUseIndexedExternalAOTFanout(context)
                               : canUseStaticAOTFanout(context)))
    return false;
  uint32_t staticID = 0;
  int64_t staticOffset = 0;
  if (!decodeNativeStatic(stableID, staticID, staticOffset) || staticOffset < 0)
    return false;
  uint64_t publishedLow = static_cast<uint64_t>(staticOffset);
  if (!context->nativeScheduleFanoutEntryCount)
    return true;
  const talos_rt_static_fanout_entry *begin =
      context->nativeScheduleFanoutEntries;
  const talos_rt_static_fanout_entry *end =
      begin + context->nativeScheduleFanoutEntryCount;
  uint64_t lo = 0, hi = 0;
  if constexpr (ProjectedClock || ProjectedSignal) {
    // The generated edge already scheduled its direct readers and updated
    // the complete forwarding tree. Only the remaining static runtime waits
    // can require a frame activation (IEEE 1800-2023 4.4, 9.4.2).
    if (staticID >= context->nativePeriodicRuntimeFanoutRanges.size())
      return false;
    std::tie(lo, hi) = context->nativePeriodicRuntimeFanoutRanges[staticID];
  } else {
    if (staticID < context->nativeScheduleFanoutRanges.size()) {
      std::tie(lo, hi) = context->nativeScheduleFanoutRanges[staticID];
    } else {
      auto first =
          std::lower_bound(begin, end, staticID,
                           [](const talos_rt_static_fanout_entry &entry,
                              uint32_t id) { return entry.static_state < id; });
      auto last = first;
      while (last != end && last->static_state == staticID)
        ++last;
      lo = first - begin;
      hi = last - begin;
    }
    if (hi - lo >= 8 && staticID < context->nativeFanoutWindows.size() &&
        bitWidth && bitWidth <= UINT64_MAX - publishedLow) {
      const auto &source = context->nativeFanoutWindows[staticID];
      if (!source.bounds.empty()) {
        auto [low, high] =
            bitWidth > 64
                ? transitionEnvelope(bitWidth, changed, posedge, negedge)
                : std::pair<uint64_t, uint64_t>{0, bitWidth};
        if (low == high)
          return true;
        uint64_t firstBucket = (publishedLow + low) >> source.shift;
        uint64_t lastBucket = (publishedLow + high - 1) >> source.shift;
        if (lastBucket < source.firstBucket ||
            (firstBucket >= source.firstBucket &&
             firstBucket - source.firstBucket >= source.bounds.size()))
          return true;
        lo = source
                 .bounds[std::max(firstBucket, source.firstBucket) -
                         source.firstBucket]
                 .first;
        hi = source
                 .bounds[std::min<uint64_t>(lastBucket - source.firstBucket,
                                            source.bounds.size() - 1)]
                 .second;
      }
    }
  }
  if (lo == hi)
    return true;
  // On a projected periodic clock the publication is one known bit. Match
  // its direction once, before looking up the frame of each waiting process.
  uint32_t projectedEdges = 0;
  if constexpr (ProjectedClock) {
    assert(bitWidth == 1 && changed && (*changed & 1));
    projectedEdges = (1u << TALOS_RT_WAIT_EDGE_CHANGE) |
                     (1u << TALOS_RT_WAIT_EDGE_BOTH) |
                     (1u << ((*posedge & 1) ? TALOS_RT_WAIT_EDGE_POSEDGE
                                            : TALOS_RT_WAIT_EDGE_NEGEDGE));
  }
  uint64_t publishedEnd =
      publishedLow + std::min(bitWidth, UINT64_MAX - publishedLow);
  // Installation selects the explicit route bits or the legacy metadata
  // rule. Resolve that choice once for the entire publication.
  uint32_t ingressMask = context->nativeScheduleIngressMask;
  uint32_t ingressValue = ingressMask & TALOS_RT_FANOUT_DIRECT;
  // A pending generated activation is a set member, not an occurrence log
  // (LRM 4.3, 9.4.2). Repeated writes need no new static publication when its
  // ready bit is already present and no runtime observer watches this source.
  // Keep every event for conditional/clocking/covergroup/VPI observers. The
  // ingress-pending flag must already be set; otherwise even a present bit
  // can require a new handoff notification to the calendar.
  bool coalescePending =
      UseClockIngress && !ProjectedSignal &&
      context->nativeScheduleClockIngressPending &&
      (UnobservedFanout ||
       (!context->clockOccurrences && !context->exactEvents &&
        !context->vpiObservationDemand &&
        !talos_rt_has_conditional_signal_waiters(context) &&
        !staticSignalObjectWatched(context, staticID)));
  bool published = false;
  for (uint64_t position = lo; position != hi; ++position) {
    const auto *entry =
        begin + ((ProjectedClock || ProjectedSignal)
                     ? context->nativeScheduleRuntimeFanoutIndices[position]
                     : position);
    uint64_t overlapLow = std::max(publishedLow, entry->low_bit);
    uint64_t overlapHigh =
        std::min(publishedEnd, entry->low_bit + entry->bit_width);
    if (overlapLow >= overlapHigh)
      continue;
    ++context->signalDiagnostics.aotFanoutEntries;
    if constexpr (ProjectedClock)
      if (!(projectedEdges & (1u << entry->edge)))
        continue;
    uint32_t slot = entry->actor_slot;
    // Installation validates the immutable actor, kernel and ingress-word
    // indices. The actor bound to a slot and its armed wait remain live.
    auto *actor = context->nativeScheduleActors[slot];
    if (!actor)
      continue;
    if (context->nativePeriodicPublicationHandle == stableID &&
        slot < context->nativePeriodicAliasContinuations.size() &&
        context->nativePeriodicAliasContinuations[slot] == entry->continuation)
      continue;
    if constexpr (UseClockIngress) {
      if (coalescePending &&
          (entry->reserved & ingressMask) == ingressValue) {
        const auto &kernel =
            context->nativeSchedulePlan->clock_kernels[entry->kernel];
        if (kernel.ingress_mask[entry->merged_bit / 64] &
            (uint64_t{1} << (entry->merged_bit % 64)))
          continue;
      }
    }
    if constexpr (!ProjectedClock) {
      uint64_t offset = overlapLow - publishedLow;
      uint64_t width = overlapHigh - overlapLow;
      bool matched = entry->edge == TALOS_RT_WAIT_EDGE_CHANGE
                         ? anyPackedBits(changed, offset, width)
                     : entry->edge == TALOS_RT_WAIT_EDGE_POSEDGE
                         ? anyPackedBits(posedge, offset, width)
                     : entry->edge == TALOS_RT_WAIT_EDGE_NEGEDGE
                         ? anyPackedBits(negedge, offset, width)
                         : anyPackedBits(posedge, offset, width) ||
                               anyPackedBits(negedge, offset, width);
      if (!matched)
        continue;
    }
    size_t index = context->nativeScheduleActorIndices[slot];
    if (index >= context->scheduledProcesses.size()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return true;
    }
    ScheduledProcess &scheduled = context->scheduledProcesses[index];
    bool activeSelf = context->activeLogicalProcessToken ==
                      (kNativeLogicalProcessTag | scheduled.token);
    if (activeSelf &&
        (entry->reserved & TALOS_RT_FANOUT_SUPPRESS_ACTIVE_SELF) != 0)
      continue;
    if ((actor->continuation != entry->continuation && !activeSelf) ||
        scheduled.instance != actor || !scheduled.started ||
        (scheduled.signalTriggered && !activeSelf) ||
        (scheduled.suspendKind != TALOS_RT_SUSPEND_CHANGE &&
         scheduled.suspendKind != TALOS_RT_SUSPEND_EDGE))
      continue;
    if (!published) {
      if (context->nextSchedulerSequence == 0) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return true;
      }
      uint64_t sequence = context->nextSchedulerSequence++;
      if (outSequence)
        *outSequence = sequence;
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.publications;
      published = true;
    }
    if constexpr (UseClockIngress) {
      if ((entry->reserved & ingressMask) == ingressValue) {
        const auto &kernel =
            context->nativeSchedulePlan->clock_kernels[entry->kernel];
        if (context->saif)
          talos_rt_saif_wake_actor_unlocked(context, entry->actor_slot);
        talos::runtime::publishClockKernelReady(kernel, entry->merged_bit);
        context->nativeScheduleClockIngressPending = true;
        continue;
      }
    }
    if (context->saif && !scheduled.signalTriggered)
      talos_rt_saif_wake_unlocked(context, TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG |
                                               scheduled.token);
    scheduled.signalTriggered = true;
    uint32_t node = entry->compute_node;
    if (node >= context->nativeScheduleNodes.size() ||
        node >= context->nativeScheduleReadyNodes.capacity() ||
        context->nativeScheduleNodes[node].actor_slot != slot ||
        context->nativeScheduleNodes[node].continuation !=
            entry->continuation) {
      context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
      return true;
    }
    context->nativeScheduleReadyNodes.set(node);
    context->nativePollCandidates.insert(scheduled.token);
    if (++context->schedulerSelectionGeneration == 0)
      context->schedulerSelectionGeneration = 1;
    context->nativeScheduleMinimumActivatedNode =
        std::min(context->nativeScheduleMinimumActivatedNode, node);
  }
  return true;
}

bool publishStaticAOTSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t *outSequence, bool indexedExternalDeposit) {
  bool useClockIngress = context && context->nativeSchedulePlan &&
                         context->nativeSchedulePlan->clock_kernel_count != 0;
  return useClockIngress ? publishStaticAOTSignalTransitionUnlockedImpl<true>(
                               context, stableID, bitWidth, changed, posedge,
                               negedge, outSequence, indexedExternalDeposit)
                         : publishStaticAOTSignalTransitionUnlockedImpl<false>(
                               context, stableID, bitWidth, changed, posedge,
                               negedge, outSequence, indexedExternalDeposit);
}

static bool publishSignalTransitionBatchImpl(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t edgeBitOffset, uint64_t *outSequence, const uint8_t *oldValue,
    const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown) {
  if (!context || bitWidth == 0 || !changed || !posedge || !negedge)
    return context != nullptr;
  if (!anyPackedBits(changed, edgeBitOffset, bitWidth))
    return true;
  uint64_t sequence = 0;
  ClockConditionPublicationView sample{stableID, bitWidth, edgeBitOffset,
                                       newValue, newUnknown};
  return publishSignalOccurrenceUnlocked(
      context, stableID, bitWidth,
      [&](const SignalSubscription &subscription) {
        bool direct =
            subscription.target == SignalSubscription::NativeDirectWait ||
            subscription.target == SignalSubscription::DesignDirectWait;
        return signalTransitionBatchMatches(subscription, stableID, bitWidth,
                                            changed, posedge, negedge,
                                            edgeBitOffset, direct);
      },
      [&](ClockOccurrenceSubscription &subscription) {
        if (isCustomClockEdge(subscription.edge))
          return customClockTransitionMatches(
              context, subscription, stableID, bitWidth, changed, edgeBitOffset,
              oldValue, oldUnknown, newValue, newUnknown);
        return signalTransitionBatchMatches(subscription, stableID, bitWidth,
                                            changed, posedge, negedge,
                                            edgeBitOffset, true);
      },
      &sample, outSequence ? outSequence : &sequence);
}

bool talos_rt_publish_signal_transition_batch_unlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    uint64_t edgeBitOffset, uint64_t *outSequence, const uint8_t *oldValue,
    const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown) {
  if (context->coverage)
    talos_rt_coverage_record_transition_unlocked(context, stableID, bitWidth,
                                                 changed, newValue, newUnknown);
  if (context->saif)
    talos_rt_saif_record_transition_unlocked(context, stableID, bitWidth,
                                             changed, newValue, newUnknown);
  ClockOccurrenceFeatureState *feature = context->clockOccurrences.get();
  if (edgeBitOffset == 0) {
    uint64_t sequence = 0;
    if (publishStaticAOTSignalTransitionUnlocked(context, stableID, bitWidth,
                                                 changed, posedge, negedge,
                                                 &sequence, false)) {
      // Generated waits may omit generic subscriptions altogether. Publish
      // their exact fanout first, then retain the runtime subscriber walk for
      // consumers outside that table (IEEE 1800-2023 9.4.2). The walk routes
      // any already-armed native subscription to the same idempotent ingress
      // bit, never to a duplicate framed activation. Clock observers still
      // need that walk, but must not suppress the generated fanout.
      // Static fanout already delivered the generated consumers. A calendar
      // plan needs the generic walk only if this object has a live runtime
      // subscription. Registration and removal update the index under the
      // same lock.
      // Keep independent clock/covergroup occurrence streams below (9.4.2,
      // 19.5, 31.5). No occurrence sequence is needed for an unwatched object.
      uint32_t staticID = 0;
      int64_t staticOffset = 0;
      bool runtimeWatched =
          !decodeNativeStatic(stableID, staticID, staticOffset) ||
          staticSignalObjectWatched(context, staticID);
      if ((runtimeWatched &&
           ((context->nativeSchedulePlan->flags &
             TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL) ||
            (context->observedWriters &&
             context->observedWriters->rootUsers.count(staticID)))) ||
          (feature && !feature->waits.empty()) || context->exactEvents)
        return publishSignalTransitionBatchImpl(
            context, stableID, bitWidth, changed, posedge, negedge,
            edgeBitOffset, outSequence, oldValue, oldUnknown, newValue,
            newUnknown);
      if (!recordStaticClockingOutputOccurrencesUnlocked(
              context, stableID, bitWidth, changed, posedge, negedge,
              edgeBitOffset, sequence))
        return false;
      if (outSequence)
        *outSequence = sequence;
      return context->schedulerStatus == TALOS_RT_OK;
    }
  }
  return publishSignalTransitionBatchImpl(
      context, stableID, bitWidth, changed, posedge, negedge, edgeBitOffset,
      outSequence, oldValue, oldUnknown, newValue, newUnknown);
}

bool talos_rt_publish_signal_occurrence_unlocked(talos_rt_context *context,
                                                 uint64_t stableID,
                                                 uint64_t bitWidth,
                                                 uint32_t edges,
                                                 uint64_t *outSequence) {
  if (!context || bitWidth == 0 || edges == 0)
    return context != nullptr;
  uint64_t sequence = 0;
  ClockConditionPublicationView sample{stableID, bitWidth, 0, nullptr, nullptr};
  return publishSignalOccurrenceUnlocked(
      context, stableID, bitWidth,
      [&](const SignalSubscription &subscription) {
        bool direct =
            subscription.target == SignalSubscription::NativeDirectWait ||
            subscription.target == SignalSubscription::DesignDirectWait;
        return !direct || signalEdgeMatches(subscription.edge, edges);
      },
      [&](ClockOccurrenceSubscription &subscription) {
        if (isCustomClockEdge(subscription.edge))
          return customClockTransitionMatches(context, subscription, stableID,
                                              bitWidth, nullptr, 0, nullptr,
                                              nullptr, nullptr, nullptr);
        return signalEdgeMatches(subscription.edge, edges);
      },
      &sample, outSequence ? outSequence : &sequence);
}

extern "C" void talos_rt_v1_scheduler_signal(talos_rt_context *context,
                                             uint64_t bitOffset,
                                             uint64_t bitWidth,
                                             uint32_t edges) {
  if (!context || bitOffset == UINT64_MAX || bitWidth == 0 || edges == 0 ||
      (edges & ~(TALOS_RT_SIGNAL_CHANGE | TALOS_RT_SIGNAL_POSEDGE |
                 TALOS_RT_SIGNAL_NEGEDGE)) != 0)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return;
    if (context->activeExecRegion == TALOS_RT_REGION_POSTPONED) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    uint32_t objectID = 0;
    int64_t offset = 0;
    uint64_t objectWidth = 0;
    if (decodeNativeAutomatic(bitOffset, objectID, offset)) {
      auto found = context->nativeAutomaticStates.find(objectID);
      if (found == context->nativeAutomaticStates.end())
        return;
      objectWidth = found->second.bitWidth;
    } else if (decodeNativeStatic(bitOffset, objectID, offset)) {
      auto found = context->nativeStaticStates.find(objectID);
      if (found == context->nativeStaticStates.end())
        return;
      objectWidth = found->second.bitWidth;
    } else if (!decodeNativeGlobal(bitOffset, offset)) {
      return;
    }
    if (objectWidth != 0 && (offset >= static_cast<__int128>(objectWidth) ||
                             static_cast<__int128>(offset) + bitWidth <= 0))
      return;
    if (!talos_rt_publish_signal_occurrence_unlocked(context, bitOffset,
                                                     bitWidth, edges))
      return;
    if (!talos_rt_latch_conditional_signal_range_unlocked(context, bitOffset,
                                                          bitWidth, edges))
      return;
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
  }
  TALOS_RT_CATCH_ALL {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
  }
}

static inline __attribute__((always_inline)) bool
staticOnlyPublicationEnvironment(const talos_rt_context *context) {
  return !context->coverage && !context->saif && !context->clockOccurrences &&
         !context->exactEvents && !context->vpiObservationDemand &&
         !context->observerDepth && !context->observerForcesCanonicalPlane &&
         context->signalValueSnapshots.empty() &&
         context->pendingNativeComputedWaiters.empty() &&
         context->pendingDesignComputedWaiters.empty() &&
         !talos_rt_has_conditional_signal_waiters(context);
}

bool talos_rt_transition_unconsumed_unlocked(const talos_rt_context *context,
                                             uint64_t stableID) {
  uint32_t staticID = 0;
  int64_t offset = 0;
  return decodeNativeStatic(stableID, staticID, offset) &&
         staticOnlyPublicationEnvironment(context) &&
         !staticSignalObjectWatched(context, staticID);
}

// The scalar's two planes have just changed at this record's FIFO position
// (IEEE 1800-2023 4.5, 4.6(b), 9.4.2). In a uniform word every wait covers
// the entire root, so any changed bit qualifies. Only the geometry is cached.
// A dormant, terminated or differently suspended receiver must not inherit
// another receiver's wake, even when they share an ingress word.
template <bool PackedFIFO>
static bool publishPackedNBAChange(talos_rt_context *context, uint32_t id,
                                   uint64_t stableID, uint64_t width,
                                   const uint8_t *changed,
                                   const uint8_t *posedge,
                                   const uint8_t *negedge) {
  auto [first, last] = context->nativeScheduleFanoutRanges[id];
  uint64_t mask = context->scalarNBAFanoutMasks[id];
  if (!mask && first != last) {
    // Sliced, edge-sensitive or runtime-routed rows use the exact per-event
    // masks. The observer queues and snapshots are empty for this source.
    bool handled;
    if constexpr (PackedFIFO)
      handled = publishStaticAOTSignalTransitionUnlockedImpl<true, false, true>(
          context, stableID, width, changed, posedge, negedge, nullptr, false);
    else
      handled = publishStaticAOTSignalTransitionUnlocked(
          context, stableID, width, changed, posedge, negedge, nullptr);
    if (!handled)
      return false;
    if (context->schedulerStatus != TALOS_RT_OK)
      return true;
  } else if (!PackedFIFO && !canUseStaticAOTFanout(context)) {
    return false;
  } else if (mask) {
    const auto *entries = context->nativeScheduleFanoutEntries;
    const auto &kernel =
        context->nativeSchedulePlan->clock_kernels[entries[first].kernel];
    uint32_t word = entries[first].merged_bit / 64;
    uint64_t needed = mask;
    if (context->nativeScheduleClockIngressPending)
      needed &= ~kernel.ingress_mask[word];
    uint64_t armed = 0;
    if (needed) {
      for (uint64_t i = first; i != last; ++i) {
        const auto &entry = entries[i];
        uint64_t bit = uint64_t{1} << (entry.merged_bit % 64);
        if (!(needed & bit))
          continue;
        auto *actor = context->nativeScheduleActors[entry.actor_slot];
        if (!actor)
          continue;
        size_t index = context->nativeScheduleActorIndices[entry.actor_slot];
        if (index >= context->scheduledProcesses.size())
          return false;
        const auto &process = context->scheduledProcesses[index];
        if (actor->continuation == entry.continuation &&
            process.instance == actor && process.started &&
            !process.signalTriggered &&
            (process.suspendKind == TALOS_RT_SUSPEND_CHANGE ||
             process.suspendKind == TALOS_RT_SUSPEND_EDGE))
          armed |= bit;
      }
    }
    context->signalDiagnostics.aotFanoutEntries += last - first;
    if (armed) {
      if (!context->nextSchedulerSequence) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return true;
      }
      ++context->nextSchedulerSequence;
      if (context->signalDiagnosticsEnabled) {
        ++context->signalDiagnostics.publications;
        ++context->scalarNBAWordPublications;
      }
      talos::runtime::publishClockKernelReadyWord(kernel, word, armed);
      context->nativeScheduleClockIngressPending = true;
    }
  }
  if (!PackedFIFO && context->nativeStateSpecializationFast)
    refreshNativeStaticSpecializationFastUnlocked(context);
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
  return true;
}

bool publishScalarNBAChangeUnlocked(talos_rt_context *context,
                                    uint64_t stableID, uint64_t width,
                                    uint64_t changed, uint64_t posedge,
                                    uint64_t negedge) {
  uint32_t id;
  int64_t offset;
  if (!decodeNativeStatic(stableID, id, offset) ||
      id >= context->scalarNBAFanoutMasks.size() ||
      context->activeLogicalProcessToken ||
      !talos_rt_transition_unconsumed_unlocked(context, stableID))
    return false;
  return publishPackedNBAChange<false>(
      context, id, stableID, width, reinterpret_cast<const uint8_t *>(&changed),
      reinterpret_cast<const uint8_t *>(&posedge),
      reinterpret_cast<const uint8_t *>(&negedge));
}

// Intersect one actual delta with the source's precomputed sensitivity
// ranges. The record can start in the middle of a source word.
static uint64_t matchPackedNBAChange(const PackedNBAChangeMap &map,
                                     const PackedNBAChangeMap::Root &root,
                                     uint64_t offset, uint64_t delta) {
  if (!delta || !root.words)
    return 0;
  auto match = [&](size_t word, uint64_t bits) {
    const auto &part = map.words[root.firstWord + word];
    uint64_t rows = part.all;
    for (size_t i = 0; i < part.masks; ++i) {
      const auto &mask = map.masks[part.firstMask + i];
      if (bits & mask.bits)
        rows |= mask.rows;
    }
    return rows;
  };
  size_t word = offset / 64;
  unsigned shift = offset % 64;
  uint64_t low = delta << shift;
  uint64_t rows = low ? match(word, low) : 0;
  if (shift && (delta >> (64 - shift)))
    rows |= match(word + 1, delta >> (64 - shift));
  return rows;
}

static void publishMappedNBAChange(talos_rt_context *context, size_t first,
                                   uint64_t rows) {
  // The map contains only direct CHANGE rows. Their fixed ingress address
  // says where a wake goes, while the live frame decides if it is armed.
  bool published = false;
  while (rows) {
    unsigned bit = __builtin_ctzll(rows);
    rows &= rows - 1;
    const auto &row = context->nativeScheduleFanoutEntries[first + bit];
    const auto &kernel = context->nativeSchedulePlan->clock_kernels[row.kernel];
    ++context->signalDiagnostics.aotFanoutEntries;
    if (context->nativeScheduleClockIngressPending &&
        kernel.ingress_mask[row.merged_bit / 64] &
            (uint64_t{1} << (row.merged_bit % 64)))
      continue;
    auto *actor = context->nativeScheduleActors[row.actor_slot];
    if (!actor || actor->continuation != row.continuation)
      continue;
    size_t index = context->nativeScheduleActorIndices[row.actor_slot];
    if (index >= context->scheduledProcesses.size()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    const auto &process = context->scheduledProcesses[index];
    if (process.instance != actor || !process.started ||
        process.signalTriggered ||
        (process.suspendKind != TALOS_RT_SUSPEND_CHANGE &&
         process.suspendKind != TALOS_RT_SUSPEND_EDGE))
      continue;
    if (!published) {
      if (!context->nextSchedulerSequence) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return;
      }
      ++context->nextSchedulerSequence;
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.publications;
      published = true;
    }
    talos::runtime::publishClockKernelReady(kernel, row.merged_bit);
    context->nativeScheduleClockIngressPending = true;
  }
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
  if (context->signalDiagnosticsEnabled)
    ++context->packedNBAChanges->publications;
}

static uint64_t matchPackedNBAImage(const PackedNBAChangeMap &map,
                                    const PackedNBAChangeMap::Root &root,
                                    uint64_t offset, uint64_t width,
                                    const uint8_t *old, const uint8_t *next) {
  uint64_t rows = root.all;
  if (!root.words)
    return rows;
  uint64_t words = width / 64, i = 0;
  while (i < words) {
    if (!(offset % 64)) {
      const auto &part = map.words[root.firstWord + offset / 64 + i];
      if (!part.masks) {
        uint64_t count = std::min<uint64_t>(words - i, part.run);
        if ((part.all & ~rows) &&
            std::memcmp(old + i * 8, next + i * 8, count * 8))
          rows |= part.all;
        i += count;
        continue;
      }
    }
    uint64_t delta = loadPackedWord<uint64_t>(old + i * 8) ^
                     loadPackedWord<uint64_t>(next + i * 8);
    rows |= matchPackedNBAChange(map, root, offset + i * 64, delta);
    ++i;
  }
  if (uint64_t tail = width % 64) {
    uint64_t delta = loadPackedBytes(old, words * 64, tail) ^
                     loadPackedBytes(next, words * 64, tail);
    rows |= matchPackedNBAChange(map, root, offset + words * 64, delta);
  }
  return rows;
}

// Replay one contiguous part of the ordinary queue under the barrier's
// shared-image and static-fanout proof. No source process runs between NBA
// records (1800-2023 4.5, 4.6(b), 10.4.2). A source with a synchronous
// observer, a change in knownness, or an extended transaction hands the
// still-unconsumed record back to canonical replay. In particular an UPF
// retention decision is made at the original update (1801-2018 9.7.3).
size_t replayPackedFIFOPrefixUnlocked(talos_rt_context *context,
                                      uint32_t region, size_t start,
                                      bool &changed, bool &knownnessChange) {
  knownnessChange = false;
  const auto *plan = context->nativeSchedulePlan;
  if (context->scalarNBAFanoutMasks.empty() || !context->packedNBAChanges ||
      !plan || !plan->state_value || context->activeLogicalProcessToken ||
      context->vpiState || context->powerNBAs || !context->forceMask.empty() ||
      !context->assignMask.empty() || !context->stateValue.shared() ||
      plan->state_bit_count != context->nativeStateBitCount ||
      plan->state_value != context->nativeStateValue ||
      plan->state_unknown != context->nativeStateUnknown ||
      plan->state_value !=
          reinterpret_cast<const uint8_t *>(context->stateValue.data()) ||
      plan->state_unknown !=
          reinterpret_cast<const uint8_t *>(context->stateUnknown.data()) ||
      !staticOnlyPublicationEnvironment(context) ||
      !canUseStaticAOTFanout(context))
    return start;

  NativeNBAUpdateScope scope(*context);
  CanonicalLimb *values = context->stateValue.data();
  const CanonicalLimb *unknowns = context->stateUnknown.data();
  const auto &changeMap = *context->packedNBAChanges;
  std::vector<uint64_t> wideMasks;
  bool published = false;
  size_t index = start;
  while (index < context->scheduledNBAs.size()) {
    const auto &update = context->scheduledNBAs[index];
    if (update.cancelled || update.execRegion != region ||
        update.dueTime > context->schedulerTime)
      break;
    uint32_t id = update.packedStaticState;
    bool boundScalar = id != 0;
    uint64_t width = update.bitWidth, bit, offset;
    if (boundScalar) {
      // This capture checked the same immutable plan, bounds and plane
      // pointers. Eligibility of its receivers still belongs to this barrier.
      bit = update.packedPlaneBit;
      offset = bit - context->nativeScheduleStaticStateIndex[id].bitOffset;
    } else {
      int64_t local;
      if (update.planeBitCount != plan->state_bit_count ||
          update.valuePlane != plan->state_value ||
          (update.unknownPlane && update.unknownPlane != plan->state_unknown) ||
          !decodeNativeStatic(update.bitOffset, id, local) || local < 0 ||
          id >= context->scalarNBAFanoutMasks.size())
        break;
      offset = uint64_t(local);
      const auto &state = context->nativeScheduleStaticStateIndex[id];
      if (!width || offset > state.bitWidth ||
          width > state.bitWidth - offset ||
          state.bitOffset > plan->state_bit_count ||
          state.bitWidth > plan->state_bit_count - state.bitOffset)
        break;
      bit = state.bitOffset + offset;
    }
    if (staticSignalObjectWatched(context, id))
      break;
    uint64_t scalarMasks[3];
    uint64_t *masks = scalarMasks;
    uint64_t words = 1 + (width - 1) / 64;
    const auto &route = changeMap.roots[id];
    bool mapped = route.all || route.words;
    uint64_t readyRows = route.all;
    if (boundScalar || update.inlinePacked) {
      // Only enqueueGenericScalar sets packedPlaneBit. Richer captures,
      // including clocking and inertial updates, keep the invalid address.
      if (!boundScalar && (width > 64 || update.packedPlaneBit != bit))
        break;
      uint64_t mask = packedWidthMask(width);
      uint64_t limb = bit / 64, shift = bit % 64;
      bool oneWord = width <= 64 - shift;
      uint64_t unknown =
          oneWord ? (unknowns ? (unknowns[limb] >> shift) & mask : 0)
                  : loadPackedBits(context->stateUnknown, bit, width);
      if (unknown != update.inlineUnknown) {
        knownnessChange = true;
        break;
      }
      // A scalar contained in one native word needs just one load and a
      // masked change of that same word. Preserve unrelated packed fields.
      uint64_t old = oneWord ? (values[limb] >> shift) & mask
                             : loadPackedBits(context->stateValue, bit, width);
      uint64_t delta = old ^ update.inlineValue;
      if (!delta) {
        ++index;
        continue;
      }
      if (mapped) {
        readyRows |=
            matchPackedNBAChange(changeMap, route, uint64_t(offset), delta);
      } else {
        scalarMasks[0] = delta;
        scalarMasks[1] = delta & ~unknown & ~old;
        scalarMasks[2] = delta & ~unknown & old;
      }
      if (oneWord)
        values[limb] ^= delta << shift;
      else
        storePackedBits(context->stateValue, bit, width, update.inlineValue);
    } else {
      uint64_t bytes = 1 + (width - 1) / 8;
      if (width <= 64 || update.retainedAutomaticID || update.stringValue ||
          update.managedValue || update.realWidth || update.driver ||
          update.commitGuard != NBACommitGuard::None ||
          update.inertialNetBit != UINT64_MAX ||
          update.inertialPathBit != UINT64_MAX ||
          update.clockingOutput != UINT64_MAX || update.value.size() != bytes ||
          (update.unknownPlane ? update.unknown.size() != bytes
                               : !update.unknown.empty()) ||
          words > wideMasks.max_size() / 3)
        break;
      const uint8_t *newUnknown =
          update.unknown.empty() ? nullptr : update.unknown.data();
      // An aligned byte image can be checked as a whole before its single
      // FIFO publication. A short final word still reads exactly its bytes.
      bool byteImage =
          !(bit % 8) && !(width % 8) && (!plan->state_unknown || newUnknown);
      uint8_t *oldBytes = plan->state_value + bit / 8;
      const uint8_t *oldUnknownBytes =
          plan->state_unknown ? plan->state_unknown + bit / 8 : nullptr;
      if (byteImage) {
        if (oldUnknownBytes &&
            std::memcmp(oldUnknownBytes, newUnknown, bytes)) {
          knownnessChange = true;
          break;
        }
        if (!std::memcmp(oldBytes, update.value.data(), bytes)) {
          ++index;
          continue;
        }
        auto [first, last] = context->nativeScheduleFanoutRanges[id];
        if (mapped || first == last) {
          if (mapped)
            readyRows = matchPackedNBAImage(changeMap, route, offset, width,
                                            oldBytes, update.value.data());
          std::memcpy(oldBytes, update.value.data(), bytes);
          published = changed = true;
          if (mapped)
            publishMappedNBAChange(context, first, readyRows);
          else if (++context->schedulerEpoch == 0)
            context->schedulerEpoch = 1;
          ++index;
          if (context->schedulerStatus != TALOS_RT_OK)
            break;
          continue;
        }
      }
      if (!mapped) {
        TALOS_RT_TRY { wideMasks.resize(words * 3); }
        TALOS_RT_CATCH(const std::bad_alloc &) {
          // Replay this unconsumed record through the ordinary commit path.
          break;
        }
        masks = wideMasks.data();
      }
      bool different = false;
      for (uint64_t word = 0; word < words; ++word) {
        uint64_t low = word * 64, n = std::min<uint64_t>(64, width - low);
        auto record = [&](uint64_t old, uint64_t next, uint64_t unknown) {
          uint64_t delta = old ^ next;
          different |= delta != 0;
          if (mapped) {
            readyRows |= matchPackedNBAChange(changeMap, route,
                                              uint64_t(offset) + low, delta);
          } else {
            masks[word] = delta;
            masks[words + word] = delta & ~unknown & ~old;
            masks[2 * words + word] = delta & ~unknown & old;
          }
        };
        if (byteImage && n == 64) {
          uint64_t byte = low / 8;
          record(loadPackedWord<uint64_t>(oldBytes + byte),
                 loadPackedWord<uint64_t>(update.value.data() + byte),
                 oldUnknownBytes
                     ? loadPackedWord<uint64_t>(oldUnknownBytes + byte)
                     : 0);
        } else {
          uint64_t unknown =
              loadPackedBits(context->stateUnknown, bit + low, n);
          if (!byteImage && unknown != loadPackedBytes(newUnknown, low, n)) {
            knownnessChange = true;
            break;
          }
          record(loadPackedBits(context->stateValue, bit + low, n),
                 loadPackedBytes(update.value.data(), low, n), unknown);
        }
      }
      if (knownnessChange)
        break;
      if (!different) {
        ++index;
        continue;
      }
      // All lanes have been checked. No observer can see a partly applied
      // packed assignment (1800-2023 4.6(b), 9.4.2, 10.4.2).
      if (byteImage)
        std::memcpy(oldBytes, update.value.data(), bytes);
      else
        for (uint64_t word = 0; word < words; ++word)
          if (mapped || masks[word]) {
            uint64_t low = word * 64, n = std::min<uint64_t>(64, width - low);
            storePackedBits(context->stateValue, bit + low, n,
                            loadPackedBytes(update.value.data(), low, n));
          }
    }
    published = changed = true;
    auto bytes = [](const uint64_t *p) {
      return reinterpret_cast<const uint8_t *>(p);
    };
    if (mapped) {
      publishMappedNBAChange(context, context->nativeScheduleFanoutRanges[id].first, readyRows);
    } else if (!publishPackedNBAChange<true>(context, id, update.bitOffset, width,
                                      bytes(masks), bytes(masks + words),
                                      bytes(masks + 2 * words))) {
      // An invalid live actor index takes the table's normal error path.
      publishStaticAOTSignalTransitionUnlockedImpl<true, false, true>(
          context, update.bitOffset, width, bytes(masks), bytes(masks + words),
          bytes(masks + 2 * words), nullptr, false);
    }
    ++index;
    if (context->schedulerStatus != TALOS_RT_OK)
      break;
  }
  if (published && context->nativeStateSpecializationFast &&
      context->schedulerStatus == TALOS_RT_OK)
    refreshNativeStaticSpecializationFastUnlocked(context);
  if (context->signalDiagnosticsEnabled)
    context->packedFIFOReplays += index - start;
  return index;
}

bool publishNativeSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    const uint8_t *oldValue, const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown, bool establishesOverride,
    bool generatedIngress) {
  // Generated native code may have committed later source stores to its
  // private plane before publishing this transition. Advance the canonical
  // plane one publication at a time so observer evaluators see source-order
  // state: prior publications plus this transition, never future stores.
  uint32_t publishedStaticID = 0;
  int64_t publishedOffset = 0;
  bool publishedStatic =
      decodeNativeStatic(bitOffset, publishedStaticID, publishedOffset);
  bool publishedGlobal =
      !publishedStatic && decodeNativeGlobal(bitOffset, publishedOffset);
  // LRM 4.3, 4.6, 9.4.2: shared generated storage is already the canonical
  // publication image. With no source observer or override, a blocking write
  // only needs to activate its exact fanout. In particular, startup functions
  // need not enter snapshot/observer bookkeeping for every initialized word.
  // Keep the normal path whenever any publication-time side effect is live.
  // Either fast path below needs a static object nobody consumes; evaluate
  // that only when one of them can apply.
  bool unconsumed =
      publishedStatic && !establishesOverride &&
      (!context->nativeSchedulePlan || context->stateValue.shared()) &&
      staticOnlyPublicationEnvironment(context) &&
      !staticSignalObjectWatched(context, publishedStaticID);
  if (unconsumed && context->forceMask.empty() && context->assignMask.empty() &&
      context->stateValue.shared() && context->stateUnknown.shared() &&
      (cleanCalendarOwnsFanout<true>(context) ||
       canUseStaticAOTFanout(context))) {
    // With an outstanding clock handoff, the full walk would ignore every
    // matching direct bit already set by this generated publication. Walk
    // the residual rows alone. An observer, override or a different
    // calendar keeps the ordinary record-by-record path (4.5, 9.4.2).
    bool projected =
        generatedIngress && context->nativeScheduleClockIngressPending &&
        !context->powerNBAs && !context->nativeScheduleExternalWritePending &&
        activeNativeAOTContext == context &&
        lockedNativeAOTContext == context &&
        publishedStaticID < context->nativePeriodicRuntimeFanoutRanges.size();
    bool delivered;
    if (projected)
      delivered =
          publishStaticAOTSignalTransitionUnlockedImpl<true, false, true, true>(
              context, bitOffset, bitWidth, changed, posedge, negedge, nullptr,
              false);
    else if (context->nativeSchedulePlan->clock_kernel_count)
      delivered =
          publishStaticAOTSignalTransitionUnlockedImpl<true, false, true>(
              context, bitOffset, bitWidth, changed, posedge, negedge, nullptr,
              false);
    else
      delivered =
          publishStaticAOTSignalTransitionUnlockedImpl<false, false, true>(
              context, bitOffset, bitWidth, changed, posedge, negedge, nullptr,
              false);
    if (delivered) {
      // Readiness does not alter the clean-environment specialization proof.
      if (++context->schedulerEpoch == 0)
        context->schedulerEpoch = 1;
      return context->schedulerStatus == TALOS_RT_OK;
    }
  }
  const NativeStaticState *publishedState =
      publishedStatic ? findNativeStaticState(context, publishedStaticID)
                      : nullptr;
  auto canonicalBit = [&](uint64_t bit, uint64_t &absolute) {
    int64_t local = 0;
    if (bit > static_cast<uint64_t>(INT64_MAX) ||
        !addHandleOffset(publishedOffset, bit, local) || local < 0)
      return false;
    absolute = static_cast<uint64_t>(local);
    if (publishedStatic) {
      if (!publishedState || absolute >= publishedState->bitWidth)
        return false;
      absolute += publishedState->bitOffset;
    } else if (!publishedGlobal) {
      return false;
    }
    return absolute < context->stateValue.size() * uint64_t{64} &&
           absolute < context->stateUnknown.size() * uint64_t{64};
  };

  // IEEE 1800-2017 10.6.2: a force overrides every driver of its target until
  // the target is released, so a driver that changes behind an active override
  // is not a value change. Generated code computes this transition from its own
  // plane, which does not model the override, so drop the overridden bits here.
  // They must not wake a waiter, and above all they must not reach the
  // canonical plane: release resolves the target from its drivers and compares
  // the result against that plane to decide whether the net changed.
  // The publication that installs an override is exempt: it carries the very
  // value the mask was just set to describe, and IEEE 1800-2017 9.4.2 makes
  // that a value change like any other, so it has to reach waiters.
  std::vector<uint8_t> overriddenChanged;
  std::vector<uint8_t> overriddenPosedge;
  std::vector<uint8_t> overriddenNegedge;
  // A held VPI put on a net (IEEE 1800-2023 38.34) overrides its drivers the
  // same way until one changes; the native store that saw the change has
  // already ended the hold. A put allocates forceMask, so this path runs.
  if (!establishesOverride &&
      (!context->forceMask.empty() || !context->assignMask.empty())) {
    size_t byteCount = static_cast<size_t>((bitWidth + 7) / 8);
    for (uint64_t bit = 0; bit != bitWidth; ++bit) {
      uint64_t absolute = 0;
      if (!byteBit(changed, bit) || !canonicalBit(bit, absolute))
        continue;
      uint64_t limb = absolute / 64;
      uint64_t mask = uint64_t{1} << (absolute % 64);
      if ((limb >= context->forceMask.size() ||
           (context->forceMask[limb] & mask) == 0) &&
          (limb >= context->assignMask.size() ||
           (context->assignMask[limb] & mask) == 0) &&
          (limb >= context->netDepositMask.size() ||
           (context->netDepositMask[limb] & mask) == 0))
        continue;
      if (overriddenChanged.empty()) {
        overriddenChanged.assign(changed, changed + byteCount);
        if (posedge)
          overriddenPosedge.assign(posedge, posedge + byteCount);
        if (negedge)
          overriddenNegedge.assign(negedge, negedge + byteCount);
      }
      setByteBit(overriddenChanged.data(), bit, false);
      if (posedge)
        setByteBit(overriddenPosedge.data(), bit, false);
      if (negedge)
        setByteBit(overriddenNegedge.data(), bit, false);
    }
    if (!overriddenChanged.empty()) {
      changed = overriddenChanged.data();
      if (posedge)
        posedge = overriddenPosedge.data();
      if (negedge)
        negedge = overriddenNegedge.data();
    }
  }

  uint64_t firstCanonicalBit = 0;
  uint64_t lastCanonicalBit = 0;
  bool packedCanonical = bitWidth != 0 && canonicalBit(0, firstCanonicalBit) &&
                         canonicalBit(bitWidth - 1, lastCanonicalBit);
  // Shared storage is admitted only without source-order observer snapshots
  // (IEEE 1800-2023 4.6(a), 9.4.2). The generated store already committed it;
  // replaying an earlier publication must not rewind a later source store.
  if (context->stateValue.shared()) {
    // No separate publication image to advance.
  } else if (packedCanonical) {
    // IEEE 1800-2023 4.6(a), 9.4.2: preserve source-order publication and
    // observation of this complete value change. Merge its bounded payload
    // with word operations instead of revisiting every bit.
    for (uint64_t bit = 0; bit < bitWidth; bit += 64) {
      uint64_t width = std::min<uint64_t>(64, bitWidth - bit);
      uint64_t mask = loadPackedBytes(changed, bit, width);
      if (!mask)
        continue;
      uint64_t value = loadPackedBytes(newValue, bit, width);
      uint64_t unknown =
          newUnknown ? loadPackedBytes(newUnknown, bit, width) : 0;
      uint64_t absolute = firstCanonicalBit + bit;
      storePackedBits(
          context->stateValue, absolute, width,
          (loadPackedBits(context->stateValue, absolute, width) & ~mask) |
              (value & mask));
      storePackedBits(
          context->stateUnknown, absolute, width,
          (loadPackedBits(context->stateUnknown, absolute, width) & ~mask) |
              (unknown & mask));
    }
  } else
    for (uint64_t bit = 0; bit != bitWidth; ++bit) {
      uint64_t absolute = 0;
      if (!byteBit(changed, bit) || !canonicalBit(bit, absolute))
        continue;
      uint64_t mask = uint64_t{1} << (absolute % 64);
      auto valueLimb = context->stateValue[absolute / 64];
      auto unknownLimb = context->stateUnknown[absolute / 64];
      valueLimb = byteBit(newValue, bit) ? valueLimb | mask : valueLimb & ~mask;
      unknownLimb = newUnknown && byteBit(newUnknown, bit)
                        ? unknownLimb | mask
                        : unknownLimb & ~mask;
    }
  // With no generated fanout either (no native schedule plan), an unconsumed
  // transition is only its change of state, now in the canonical plane (IEEE
  // 1800-2023 4.3: executing an update event considers the processes
  // sensitive to it for evaluation; here there are none; two-tier B2 Q4).
  // Overridden bits were dropped above and the rest is in the canonical
  // plane, so force and assign masks do not matter here. Signal diagnostics
  // count publications, so they keep the full path.
  if (unconsumed && !context->nativeSchedulePlan &&
      !context->signalDiagnosticsEnabled) {
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
    return context->schedulerStatus == TALOS_RT_OK;
  }
  // IEEE 1800-2023 4.6(a), 4.9.3: commit the complete publication image
  // before enabling its synchronous observers. A nested publication from a
  // sampler must not be overwritten by replaying this older update afterward.
  // This ordering also supplies the event-time state required by IEEE
  // 1801-2018 6.50 for retention save/restore sampling. Keep the original
  // old/new payloads and edge masks for observers of this particular event.
  return publishCommittedSignalTransitionUnlocked(
      context, bitOffset, bitWidth, changed, posedge, negedge, oldValue,
      oldUnknown, newValue, newUnknown);
}

bool publishCommittedSignalTransitionUnlocked(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    const uint8_t *changed, const uint8_t *posedge, const uint8_t *negedge,
    const uint8_t *oldValue, const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown) {
  uint64_t sequence = 0;
  if (!talos_rt_publish_signal_transition_batch_unlocked(
          context, bitOffset, bitWidth, changed, posedge, negedge, 0, &sequence,
          oldValue, oldUnknown, newValue, newUnknown))
    return false;
  talos_rt_invalidate_signal_snapshots_unlocked(context, bitOffset, bitWidth);
  if (talos_rt_has_conditional_signal_waiters(context)) {
    for (uint64_t bit = 0; bit != bitWidth; ++bit) {
      if (!byteBit(changed, bit) || bit > static_cast<uint64_t>(INT64_MAX))
        continue;
      uint64_t eventHandle =
          nativeHandleOffset(bitOffset, static_cast<int64_t>(bit));
      if (eventHandle == UINT64_MAX)
        continue;
      context->signalValueSnapshots[eventHandle] = {
          sequence, byteBit(newValue, bit),
          newUnknown && byteBit(newUnknown, bit)};
    }
    bool latchable =
        talos_rt_conditional_event_relevant(context, bitOffset, bitWidth);
    for (uint64_t bit = 0; latchable && bit != bitWidth; ++bit) {
      if (!byteBit(changed, bit) || bit > static_cast<uint64_t>(INT64_MAX))
        continue;
      uint64_t eventHandle =
          nativeHandleOffset(bitOffset, static_cast<int64_t>(bit));
      if (eventHandle == UINT64_MAX)
        continue;
      uint32_t edges = TALOS_RT_SIGNAL_CHANGE;
      if (byteBit(posedge, bit))
        edges |= TALOS_RT_SIGNAL_POSEDGE;
      if (byteBit(negedge, bit))
        edges |= TALOS_RT_SIGNAL_NEGEDGE;
      if (!talos_rt_latch_conditional_signal_waiters_unlocked(
              context, eventHandle, edges))
        return false;
    }
  }
  bool previousCanonicalPlane = context->observerForcesCanonicalPlane;
  context->observerForcesCanonicalPlane = true;
  bool observerStatus =
      talos_rt_notify_observer_signal_unlocked(context, bitOffset, bitWidth);
  context->observerForcesCanonicalPlane = previousCanonicalPlane;
  if (context->nativeStateSpecializationFast)
    refreshNativeStaticSpecializationFastUnlocked(context);
  if (!observerStatus)
    return false;
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
  return true;
}

namespace {

void schedulerSignalTransition(talos_rt_context *context, uint64_t bitOffset,
                               uint64_t bitWidth, const uint8_t *oldValue,
                               const uint8_t *oldUnknown,
                               const uint8_t *newValue,
                               const uint8_t *newUnknown,
                               bool establishesOverride,
                               bool generatedIngress = false) {
  if (!context || bitOffset == UINT64_MAX || bitWidth == 0 ||
      bitWidth > UINT64_MAX - 7 || !oldValue || !newValue)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return;
    // Equal captured buffers cannot contain a value or X/Z transition.
    // Different padding or a missing unknown plane falls through to the
    // bit-accurate comparison (1800-2023 9.4.2, Table 9-2).
    uint64_t bytes = (bitWidth + 7) / 8;
    if (bytes <= SIZE_MAX && !std::memcmp(oldValue, newValue, bytes) &&
        (oldUnknown == newUnknown ||
         (oldUnknown && newUnknown &&
          !std::memcmp(oldUnknown, newUnknown, bytes))))
      return;
    // A range inside one static or automatic state has every bit in range,
    // so its edge masks can be built a word at a time.
    bool packedRange = true;
    uint32_t stateID = 0;
    int64_t stateOffset = 0;
    if (decodeNativeStatic(bitOffset, stateID, stateOffset)) {
      const NativeStaticState *state = findNativeStaticState(context, stateID);
      packedRange =
          state && stateOffset >= 0 &&
          static_cast<uint64_t>(stateOffset) <= state->bitWidth &&
          bitWidth <= state->bitWidth - static_cast<uint64_t>(stateOffset);
    } else if (decodeNativeAutomatic(bitOffset, stateID, stateOffset)) {
      auto found = context->nativeAutomaticStates.find(stateID);
      packedRange =
          found != context->nativeAutomaticStates.end() && stateOffset >= 0 &&
          static_cast<uint64_t>(stateOffset) <= found->second.bitWidth &&
          bitWidth <=
              found->second.bitWidth - static_cast<uint64_t>(stateOffset);
    } else {
      packedRange = false;
    }
    if (packedRange && bitWidth <= 64) {
      uint64_t widthMask = packedWidthMask(bitWidth);
      uint64_t oldValueBits =
          loadPackedBytes(oldValue, 0, bitWidth) & widthMask;
      uint64_t oldUnknownBits =
          oldUnknown ? loadPackedBytes(oldUnknown, 0, bitWidth) & widthMask : 0;
      uint64_t newValueBits =
          loadPackedBytes(newValue, 0, bitWidth) & widthMask;
      uint64_t newUnknownBits =
          newUnknown ? loadPackedBytes(newUnknown, 0, bitWidth) & widthMask : 0;
      uint64_t changedBits =
          (oldValueBits ^ newValueBits) | (oldUnknownBits ^ newUnknownBits);
      if (changedBits == 0)
        return;
      uint64_t oldZero = ~oldUnknownBits & ~oldValueBits & widthMask;
      uint64_t oldOne = ~oldUnknownBits & oldValueBits & widthMask;
      uint64_t newZero = ~newUnknownBits & ~newValueBits & widthMask;
      uint64_t newOne = ~newUnknownBits & newValueBits & widthMask;
      uint64_t posedgeBits =
          ((oldZero & ~newZero) | (oldUnknownBits & newOne)) & widthMask;
      uint64_t negedgeBits =
          ((oldOne & ~newOne) | (oldUnknownBits & newZero)) & widthMask;
      (void)publishNativeSignalTransitionUnlocked(
          context, bitOffset, bitWidth,
          reinterpret_cast<const uint8_t *>(&changedBits),
          reinterpret_cast<const uint8_t *>(&posedgeBits),
          reinterpret_cast<const uint8_t *>(&negedgeBits), oldValue, oldUnknown,
          newValue, newUnknown, establishesOverride, generatedIngress);
      return;
    }
    PackedSignalTransitionBuffer transitions(bitWidth);
    bool changed = false;
    if (packedRange) {
      // IEEE 1800-2023 9.4.2, Table 9-2: build the per-bit four-state edge
      // masks before publishing. Publishing each word would split one SV
      // assignment into several observable updates. Subscription matching
      // still selects only the expression's LSB for posedge/negedge (9.4.2).
      for (uint64_t bit = 0; bit < bitWidth; bit += 64) {
        uint64_t width = std::min<uint64_t>(64, bitWidth - bit);
        uint64_t mask = packedWidthMask(width);
        uint64_t oldV = loadPackedBytes(oldValue, bit, width);
        uint64_t oldU =
            oldUnknown ? loadPackedBytes(oldUnknown, bit, width) : 0;
        uint64_t newV = loadPackedBytes(newValue, bit, width);
        uint64_t newU =
            newUnknown ? loadPackedBytes(newUnknown, bit, width) : 0;
        uint64_t delta = (oldV ^ newV) | (oldU ^ newU);
        uint64_t oldZero = ~oldU & ~oldV;
        uint64_t oldOne = ~oldU & oldV;
        uint64_t newZero = ~newU & ~newV;
        uint64_t newOne = ~newU & newV;
        storePackedBytes(transitions.changed(), bit, width, delta);
        storePackedBytes(transitions.posedge(), bit, width,
                         ((oldZero & ~newZero) | (oldU & newOne)) & mask);
        storePackedBytes(transitions.negedge(), bit, width,
                         ((oldOne & ~newOne) | (oldU & newZero)) & mask);
        changed |= delta != 0;
      }
      if (changed)
        (void)publishNativeSignalTransitionUnlocked(
            context, bitOffset, bitWidth, transitions.changed(),
            transitions.posedge(), transitions.negedge(), oldValue, oldUnknown,
            newValue, newUnknown, establishesOverride, generatedIngress);
      return;
    }
    for (uint64_t bit = 0; bit != bitWidth; ++bit) {
      bool oldValueBit = byteBit(oldValue, bit);
      bool oldUnknownBit = oldUnknown && byteBit(oldUnknown, bit);
      bool newValueBit = byteBit(newValue, bit);
      bool newUnknownBit = newUnknown && byteBit(newUnknown, bit);
      uint32_t edges = transitionEdges(oldValueBit, oldUnknownBit, newValueBit,
                                       newUnknownBit);
      if (edges == 0)
        continue;
      if (bit > static_cast<uint64_t>(INT64_MAX))
        continue;
      uint64_t eventHandle =
          nativeHandleOffset(bitOffset, static_cast<int64_t>(bit));
      uint32_t automaticID = 0;
      uint32_t staticID = 0;
      int64_t eventOffset = 0;
      bool automatic =
          decodeNativeAutomatic(eventHandle, automaticID, eventOffset);
      bool boundedStatic =
          !automatic && decodeNativeStatic(eventHandle, staticID, eventOffset);
      bool inRange = eventOffset >= 0;
      if (automatic) {
        auto found = context->nativeAutomaticStates.find(automaticID);
        inRange &= found != context->nativeAutomaticStates.end() &&
                   static_cast<uint64_t>(eventOffset) < found->second.bitWidth;
      } else if (boundedStatic) {
        auto found = context->nativeStaticStates.find(staticID);
        inRange &= found != context->nativeStaticStates.end() &&
                   static_cast<uint64_t>(eventOffset) < found->second.bitWidth;
      } else {
        inRange &= decodeNativeGlobal(eventHandle, eventOffset);
      }
      if (!inRange)
        continue;
      transitions.record(bit, edges);
      changed = true;
    }
    if (changed)
      (void)publishNativeSignalTransitionUnlocked(
          context, bitOffset, bitWidth, transitions.changed(),
          transitions.posedge(), transitions.negedge(), oldValue, oldUnknown,
          newValue, newUnknown, establishesOverride, generatedIngress);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_OUT_OF_MEMORY);
  }
  TALOS_RT_CATCH_ALL {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
  }
}

// The context whose merging publication batch this thread is executing.
thread_local talos_rt_context *publicationBatchContext = nullptr;

// The generated leaf of talos_rt_v1_scheduler_static_transition is valid
// only while the installed exact-fanout plan is the active clean AOT kernel.
// Otherwise the transition takes the ordinary transition path.
bool staticTransitionTakesOrdinaryPath(const talos_rt_context *context) {
  return activeNativeAOTContext != context || !canUseStaticAOTFanout(context) ||
         ((context->nativeSchedulePlan->flags &
           TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL) &&
          !context->nativeStaticEvalIslandCertified);
}

// IEEE 1800-2023 4.7 lets a statement without time control execute as one
// event, so no process runs between the writes of a batch. Each condition
// names a publication-time consumer of individual occurrences or of
// intermediate values: force/assign masking (10.6.2), toggle coverage, clock
// occurrences and covergroup clock events, VPI value-change callbacks (38.36.1,
// 4.10), observer evaluation, signal snapshots, and computed or conditional
// waits (9.4.2, 9.4.3). Without them, and without a runtime subscription of the
// root (checked per transition), a publication only inserts pending
// activations of the root's exact static fanout. Those are set members: a
// waiter resumes on its first matching change and is then no longer waiting
// (9.4.2), so the OR of the per-write masks selects the same waiters.
bool publicationBatchCanMerge(const talos_rt_context *context) {
  return context->schedulerStatus == TALOS_RT_OK &&
         context->forceMask.empty() && context->assignMask.empty() &&
         !context->coverage && !context->saif && !context->clockOccurrences &&
         !context->exactEvents && !context->vpiObservationDemand &&
         !context->observerDepth && !context->observerForcesCanonicalPlane &&
         context->signalValueSnapshots.empty() &&
         context->pendingNativeComputedWaiters.empty() &&
         context->pendingDesignComputedWaiters.empty() &&
         !talos_rt_has_conditional_signal_waiters(context);
}

uint64_t extractBatchBits(const uint64_t *plane, uint64_t position,
                          uint64_t width) {
  uint64_t shift = position % 64;
  uint64_t bits = plane[position / 64] >> shift;
  if (shift != 0 && shift + width > 64)
    bits |= plane[position / 64 + 1] << (64 - shift);
  return bits & packedWidthMask(width);
}

// Replace the bits selected by the width-relative mask.
void depositBatchBits(uint64_t *plane, uint64_t position, uint64_t width,
                      uint64_t mask, uint64_t bits) {
  uint64_t shift = position % 64;
  auto &low = plane[position / 64];
  low = (low & ~(mask << shift)) | ((bits & mask) << shift);
  if (shift != 0 && shift + width > 64) {
    auto &high = plane[position / 64 + 1];
    high = (high & ~(mask >> (64 - shift))) | ((bits & mask) >> (64 - shift));
  }
}

enum class BatchDeferral { Deferred, Flush, Publish };

BatchDeferral deferStaticTransitionUnlocked(
    talos_rt_context *context, uint32_t staticState, uint64_t lowBit,
    uint64_t bitWidth, uint64_t oldValue, uint64_t oldUnknown,
    uint64_t newValue, uint64_t newUnknown, uint64_t changed) {
  PublicationBatch &batch = context->publicationBatch;
  // A write under another logical identity (a fused activation's owned
  // transition) suppresses a different self wakeup, and one from another
  // AOT entry may take the generated leaf; both publish in order.
  if (!batch.merging || batch.flushing ||
      context->schedulerStatus != TALOS_RT_OK ||
      context->activeLogicalProcessToken != batch.logicalProcessToken ||
      activeNativeAOTContext != batch.aotContext ||
      staticSignalObjectWatched(context, staticState))
    return BatchDeferral::Publish;
  if (batch.staticID == 0) {
    const NativeStaticState *state =
        findNativeStaticState(context, staticState);
    if (!state || lowBit > state->bitWidth ||
        bitWidth > state->bitWidth - lowBit)
      return BatchDeferral::Publish;
    batch.staticID = staticState;
    batch.rootWidth = state->bitWidth;
    batch.windowLow = lowBit - lowBit % PublicationBatch::kWindowBits;
    batch.touchedLow = UINT64_MAX;
    batch.touchedHigh = 0;
  } else if (staticState != batch.staticID || lowBit < batch.windowLow ||
             lowBit - batch.windowLow >= PublicationBatch::kWindowBits) {
    return BatchDeferral::Flush;
  } else if (lowBit > batch.rootWidth || bitWidth > batch.rootWidth - lowBit) {
    return BatchDeferral::Publish;
  }
  uint64_t position = lowBit - batch.windowLow;
  uint64_t mask = packedWidthMask(bitWidth);
  // IEEE 1800-2023 9.4.2, Table 9-2, per write.
  uint64_t oldZero = ~oldUnknown & ~oldValue & mask;
  uint64_t oldOne = ~oldUnknown & oldValue & mask;
  uint64_t newZero = ~newUnknown & ~newValue & mask;
  uint64_t newOne = ~newUnknown & newValue & mask;
  uint64_t posedge = (oldZero & ~newZero) | (oldUnknown & newOne);
  uint64_t negedge = (oldOne & ~newOne) | (oldUnknown & newZero);
  auto deposit = [&](PublicationBatch::Plane plane, uint64_t select,
                     uint64_t bits) {
    depositBatchBits(batch.plane(plane), position, bitWidth, select, bits);
  };
  deposit(PublicationBatch::Changed, changed, changed);
  deposit(PublicationBatch::Posedge, posedge, posedge);
  deposit(PublicationBatch::Negedge, negedge, negedge);
  uint64_t unseen =
      mask & ~extractBatchBits(batch.plane(PublicationBatch::Seen), position,
                               bitWidth);
  deposit(PublicationBatch::OldValue, unseen, oldValue);
  deposit(PublicationBatch::OldUnknown, unseen, oldUnknown);
  deposit(PublicationBatch::Seen, unseen, unseen);
  deposit(PublicationBatch::NewValue, mask, newValue);
  deposit(PublicationBatch::NewUnknown, mask, newUnknown);
  batch.touchedLow = std::min(batch.touchedLow, position);
  batch.touchedHigh = std::max(batch.touchedHigh, position + bitWidth);
  return BatchDeferral::Deferred;
}

// Deliver the held window through the ordinary transition path, under the
// logical identity that executed the writes.
void flushPublicationBatch(talos_rt_context *context) {
  // Only this thread fills its batch window (publicationBatchContext).
  if (context->publicationBatch.staticID == 0)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    PublicationBatch &batch = context->publicationBatch;
    if (batch.staticID == 0 || batch.flushing)
      return;
    uint64_t firstWord = batch.touchedLow / 64;
    uint64_t lastWord = (batch.touchedHigh - 1) / 64;
    uint64_t low = batch.windowLow + firstWord * 64;
    uint64_t width = batch.windowLow + batch.touchedHigh - low;
    bool changed = false;
    for (uint64_t word = firstWord; word <= lastWord; ++word)
      changed |= batch.plane(PublicationBatch::Changed)[word] != 0;
    struct Reset {
      talos_rt_context *context;
      uint64_t firstWord, lastWord, previousToken, previousParent;
      ~Reset() {
        PublicationBatch &batch = context->publicationBatch;
        for (unsigned plane = 0; plane != PublicationBatch::PlaneCount; ++plane)
          std::fill(batch.plane(PublicationBatch::Plane(plane)) + firstWord,
                    batch.plane(PublicationBatch::Plane(plane)) + lastWord + 1,
                    uint64_t{0});
        batch.staticID = 0;
        batch.flushing = false;
        context->activeLogicalProcessToken = previousToken;
        context->activeLogicalProcessParent = previousParent;
      }
    } reset{context, firstWord, lastWord, context->activeLogicalProcessToken,
            context->activeLogicalProcessParent};
    batch.flushing = true;
    context->activeLogicalProcessToken = batch.logicalProcessToken;
    context->activeLogicalProcessParent = batch.logicalProcessParent;
    if (changed && context->schedulerStatus == TALOS_RT_OK) {
      auto bytes = [&](PublicationBatch::Plane plane) {
        return reinterpret_cast<const uint8_t *>(batch.plane(plane) +
                                                 firstWord);
      };
      (void)publishNativeSignalTransitionUnlocked(
          context,
          talos_rt_stable_handle_encode(TALOS_RT_STABLE_HANDLE_STATIC,
                                        batch.staticID,
                                        static_cast<int64_t>(low)),
          width, bytes(PublicationBatch::Changed),
          bytes(PublicationBatch::Posedge), bytes(PublicationBatch::Negedge),
          bytes(PublicationBatch::OldValue),
          bytes(PublicationBatch::OldUnknown),
          bytes(PublicationBatch::NewValue),
          bytes(PublicationBatch::NewUnknown), false);
      // Publication is the only state change inside a batch. Should it select
      // the generated leaf for later writes, they are no longer held.
      batch.merging &= staticTransitionTakesOrdinaryPath(context);
    }
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_OUT_OF_MEMORY);
  }
  TALOS_RT_CATCH_ALL {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
  }
}

bool deferBatchedStaticTransition(talos_rt_context *context,
                                  uint32_t staticState, uint64_t lowBit,
                                  uint64_t bitWidth, uint64_t oldValue,
                                  uint64_t oldUnknown, uint64_t newValue,
                                  uint64_t newUnknown, uint64_t changed) {
  for (unsigned attempt = 0; attempt != 2; ++attempt) {
    BatchDeferral result;
    {
      ContextMutexLock lock(context);
      result = deferStaticTransitionUnlocked(context, staticState, lowBit,
                                             bitWidth, oldValue, oldUnknown,
                                             newValue, newUnknown, changed);
    }
    if (result != BatchDeferral::Flush)
      return result == BatchDeferral::Deferred;
    flushPublicationBatch(context);
  }
  return false;
}

} // namespace

extern "C" talos_rt_status
talos_rt_v1_scheduler_publication_batch_begin(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    PublicationBatch &batch = context->publicationBatch;
    if (batch.depth++ != 0)
      return TALOS_RT_OK;
    // One statement executes in one context, so this replaces any marker a
    // terminally failed batch left behind on this thread.
    batch.merging = staticTransitionTakesOrdinaryPath(context) &&
                    publicationBatchCanMerge(context);
    if (!batch.merging)
      return TALOS_RT_OK;
    if (batch.words.empty())
      batch.words.assign(PublicationBatch::PlaneCount *
                             (PublicationBatch::kWindowWords + 1),
                         0);
    batch.logicalProcessToken = context->activeLogicalProcessToken;
    batch.logicalProcessParent = context->activeLogicalProcessParent;
    batch.aotContext = activeNativeAOTContext;
    publicationBatchContext = context;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    // Merging is only an optimization; publish every write instead.
    context->publicationBatch.merging = false;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_ARGUMENT; }
}

extern "C" talos_rt_status
talos_rt_v1_scheduler_publication_batch_end(talos_rt_context *context) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  {
    ContextMutexLock lock(context);
    PublicationBatch &batch = context->publicationBatch;
    if (batch.depth == 0)
      return TALOS_RT_INVALID_LIFECYCLE;
    if (--batch.depth != 0)
      return TALOS_RT_OK;
  }
  flushPublicationBatch(context);
  ContextMutexLock lock(context);
  context->publicationBatch.merging = false;
  if (publicationBatchContext == context)
    publicationBatchContext = nullptr;
  return TALOS_RT_OK;
}

extern "C" void talos_rt_v1_scheduler_signal_transition(
    talos_rt_context *context, uint64_t bitOffset, uint64_t bitWidth,
    const uint8_t *oldValue, const uint8_t *oldUnknown, const uint8_t *newValue,
    const uint8_t *newUnknown) {
  // Held batch transitions precede this one in source order.
  if (publicationBatchContext && publicationBatchContext == context)
    flushPublicationBatch(context);
  schedulerSignalTransition(context, bitOffset, bitWidth, oldValue, oldUnknown,
                            newValue, newUnknown, false);
}

// IEEE 1800-2017 10.6.2: installing a force/assign and releasing a force back
// to an active assign are value changes of the overridden target, not driver
// changes behind an override. Their masks already describe the post-transition
// ownership, so publish them exempt from ordinary override suppression.
void publishOverrideTransition(talos_rt_context *context, uint64_t bitOffset,
                               uint64_t bitWidth, const uint8_t *oldValue,
                               const uint8_t *oldUnknown,
                               const uint8_t *newValue,
                               const uint8_t *newUnknown) {
  schedulerSignalTransition(context, bitOffset, bitWidth, oldValue, oldUnknown,
                            newValue, newUnknown, true);
}

template <typename Publish>
static void publishAsNativeActor(talos_rt_context *context, uint32_t actorSlot,
                                 Publish publish) {
  if (!context)
    return;
  ContextMutexLock lock(context);
  if (actorSlot >= context->nativeScheduleActorIndices.size()) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return;
  }
  size_t index = context->nativeScheduleActorIndices[actorSlot];
  if (index >= context->scheduledProcesses.size()) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return;
  }
  // LRM 4.6(a), 9.4.2: publish at the source store, under its original
  // logical process identity. Other waiting processes receive the event;
  // the executing process must not wake its own inactive event control.
  struct PublicationScope {
    talos_rt_context *context;
    uint64_t previous, previousParent;
    ~PublicationScope() {
      context->activeLogicalProcessToken = previous;
      context->activeLogicalProcessParent = previousParent;
    }
  } scope{context, context->activeLogicalProcessToken,
          context->activeLogicalProcessParent};
  context->activeLogicalProcessToken =
      kNativeLogicalProcessTag | context->scheduledProcesses[index].token;
  context->activeLogicalProcessParent =
      context->scheduledProcesses[index].parent;
  publish();
}

// A prepared primary clock is a pure one-bit source process. Publish a
// subscribed edge under that process's identity before the implicit port
// assignments run (4.9.1, 4.10, 38.36.1). Other clock domains stay compiled.
extern "C" talos_rt_status
talos_rt_v1_publish_read_clock(talos_rt_context *context, uint32_t actor,
                               uint32_t state, uint64_t low, uint64_t oldValue,
                               uint64_t newValue, uint32_t staticPublication) {
  if (!context || activeNativeAOTContext != context ||
      lockedNativeAOTContext != context)
    return TALOS_RT_INVALID_LIFECYCLE;
  if (context->observedWriters &&
      context->observedWriters->rootUsers.count(state)) {
    uint8_t previous = oldValue & 1, current = newValue & 1;
    uint64_t handle = talos_rt_stable_handle_encode(
        TALOS_RT_STABLE_HANDLE_STATIC, state, low);
    publishAsNativeActor(context, actor, [&] {
      talos_rt_v1_scheduler_signal_transition(context, handle, 1, &previous,
                                              nullptr, &current, nullptr);
    });
  } else if (staticPublication) {
    talos_rt_v1_scheduler_static_transition(context, state, low, 1, oldValue, 0,
                                            newValue, 0);
  }
  if (context->schedulerStatus == TALOS_RT_OK &&
      context->schedulerFinishRequested.load(std::memory_order_relaxed))
    return TALOS_RT_TIER_UNAVAILABLE;
  return context->schedulerStatus;
}

extern "C" void talos_rt_v1_scheduler_static_transition_owned(
    talos_rt_context *context, uint32_t actorSlot, uint32_t staticState,
    uint64_t lowBit, uint64_t bitWidth, uint64_t oldValue, uint64_t oldUnknown,
    uint64_t newValue, uint64_t newUnknown) {
  publishAsNativeActor(context, actorSlot, [&] {
    talos_rt_v1_scheduler_static_transition(context, staticState, lowBit,
                                            bitWidth, oldValue, oldUnknown,
                                            newValue, newUnknown);
  });
}

extern "C" void talos_rt_v1_scheduler_wide_transition_owned(
    talos_rt_context *context, uint32_t actorSlot, uint64_t handle,
    uint64_t width, const uint8_t *oldValue, const uint8_t *oldUnknown,
    const uint8_t *newValue, const uint8_t *newUnknown) {
  publishAsNativeActor(context, actorSlot, [&] {
    talos_rt_v1_scheduler_signal_transition(context, handle, width, oldValue,
                                            oldUnknown, newValue, newUnknown);
  });
}

// A framed writer and the generated eval owners share one publication
// image. Resolve an in-bounds static destination once, retain a continuous
// contribution and publish the change of the *complete* packed assignment
// to the installed fanout. The original frame owns the logical process
// throughout (1800-2023 4.6(a), 9.4.2, 10.6.2).
static std::optional<uint64_t>
sharedFrameStoreOffset(talos_rt_context *context, uint8_t *valuePlane,
                       uint8_t *unknownPlane, uint64_t stateBits,
                       uint64_t handle, uint32_t width, uint32_t flags) {
  const auto *plan = context->nativeSchedulePlan;
  bool fourState = flags & TALOS_RT_FRAME_STORE_UNKNOWN;
  bool continuous = flags & TALOS_RT_FRAME_STORE_CONTINUOUS;
  if (!plan || plan->state_bit_count != stateBits ||
      plan->state_value != valuePlane || !context->activeNativeProcess ||
      context->activeExecRegion == TALOS_RT_REGION_POSTPONED ||
      context->schedulerStatus != TALOS_RT_OK || context->powerNBAs ||
      context->observerDepth || context->observerForcesCanonicalPlane ||
      context->nativeScheduleDirtyRootsPresent ||
      context->nativeScheduleExternalWritePending ||
      // A prior buffered transition has to publish first. With an empty
      // window, the ordinary transition's batch flush would do nothing.
      (publicationBatchContext == context &&
       (context->publicationBatch.staticID ||
        context->publicationBatch.flushing)) ||
      !context->stateValue.shared() ||
      valuePlane != reinterpret_cast<uint8_t *>(context->stateValue.data()) ||
      (fourState && (!unknownPlane || unknownPlane != plan->state_unknown ||
                     !context->stateUnknown.shared() ||
                     unknownPlane != reinterpret_cast<uint8_t *>(
                                         context->stateUnknown.data()))) ||
      (continuous &&
       (context->continuousMask.size() != context->stateValue.size() ||
        context->continuousValue.size() != context->stateValue.size() ||
        (fourState &&
         context->continuousUnknown.size() != context->stateUnknown.size()))))
    return std::nullopt;
  uint32_t id;
  int64_t offset;
  if (!decodeNativeStatic(handle, id, offset) || offset < 0)
    return std::nullopt;
  const auto *state = findNativeStaticState(context, id);
  if (!state || uint64_t(offset) > state->bitWidth ||
      width > state->bitWidth - uint64_t(offset) ||
      state->bitOffset > stateBits ||
      state->bitWidth > stateBits - state->bitOffset)
    return std::nullopt;
  return state->bitOffset + uint64_t(offset);
}

static bool publishFrameStore(talos_rt_context *context, uint8_t *valuePlane,
                              uint8_t *unknownPlane, uint64_t stateBits,
                              uint64_t handle, uint32_t width, uint32_t flags,
                              uint64_t value, uint64_t unknown) {
  auto at = sharedFrameStoreOffset(context, valuePlane, unknownPlane, stateBits,
                                   handle, width, flags);
  if (!at)
    return false;
  uint64_t bit = *at;
  auto *plan = context->nativeSchedulePlan;
  bool fourState = flags & TALOS_RT_FRAME_STORE_UNKNOWN;
  bool continuous = flags & TALOS_RT_FRAME_STORE_CONTINUOUS;
  uint64_t mask = packedWidthMask(width);
  value &= mask;
  unknown = fourState ? unknown & mask : 0;
  uint64_t old = loadPackedBits(context->stateValue, bit, width);
  if (!fourState && !context->twoState() && plan->state_unknown &&
      loadPackedBits(context->stateUnknown, bit, width))
    return false;
  uint64_t oldUnknown =
      fourState ? loadPackedBits(context->stateUnknown, bit, width) : 0;
  if (continuous) {
    storePackedBits(context->continuousValue, bit, width, value);
    if (fourState)
      storePackedBits(context->continuousUnknown, bit, width, unknown);
    storePackedBits(context->continuousMask, bit, width, mask);
  }
  // A force or procedural assignment hides only its selected bits. The
  // source driver contribution above still tracks the entire assignment.
  uint64_t hidden = 0;
  if (!context->forceMask.empty())
    hidden |= loadPackedBits(context->forceMask, bit, width);
  if (!context->assignMask.empty())
    hidden |= loadPackedBits(context->assignMask, bit, width);
  value = (old & hidden) | (value & ~hidden);
  unknown = (oldUnknown & hidden) | (unknown & ~hidden);
  if (oldUnknown != unknown) {
    markNativeUnknownBitsUnlocked(context, bit, width, unknown);
    publishNativeKnownnessChangeUnlocked(plan, bit, width, oldUnknown, unknown);
  }
  uint64_t change = (old ^ value) | (oldUnknown ^ unknown);
  if (!change)
    return true;
  storePackedBits(context->stateValue, bit, width, value);
  if (fourState)
    storePackedBits(context->stateUnknown, bit, width, unknown);
  uint64_t oldZero = ~oldUnknown & ~old & mask;
  uint64_t oldOne = ~oldUnknown & old & mask;
  uint64_t newZero = ~unknown & ~value & mask;
  uint64_t newOne = ~unknown & value & mask;
  uint8_t changed[8], posedge[8], negedge[8];
  storePackedWord<uint64_t>(changed, change);
  storePackedWord<uint64_t>(posedge,
                            (oldZero & ~newZero) | (oldUnknown & newOne));
  storePackedWord<uint64_t>(negedge,
                            (oldOne & ~newOne) | (oldUnknown & newZero));
  uint8_t oldBytes[8], newBytes[8], oldUnknownBytes[8], newUnknownBytes[8];
  storePackedWord<uint64_t>(oldBytes, old);
  storePackedWord<uint64_t>(newBytes, value);
  storePackedWord<uint64_t>(oldUnknownBytes, oldUnknown);
  storePackedWord<uint64_t>(newUnknownBytes, unknown);
  // Use the same source-ordered publication for direct eval owners, ranked
  // continuations and ordinary subscribers. It selects the installed fanout
  // or the full observer path at the actual update.
  (void)publishNativeSignalTransitionUnlocked(
      context, handle, width, changed, posedge, negedge, oldBytes,
      fourState ? oldUnknownBytes : nullptr, newBytes,
      fourState ? newUnknownBytes : nullptr);
  return true;
}

template <size_t Capacity>
static void checkedFrameStore(talos_rt_context *context, uint8_t *valuePlane,
                              uint8_t *unknownPlane, uint64_t stateBits,
                              uint64_t handle, uint32_t width, uint32_t flags,
                              const uint8_t *input,
                              const uint8_t *inputUnknown) {
  bool fourState = flags & TALOS_RT_FRAME_STORE_UNKNOWN;
  uint8_t old[Capacity], oldUnknown[Capacity], next[Capacity],
      nextUnknown[Capacity];
  auto read = [&](uint8_t *base, bool x, uint8_t *out) {
    return talos_rt_v1_native_state_load_plane(context, base, stateBits, handle,
                                               width, x, x, out);
  };
  auto store = flags & TALOS_RT_FRAME_STORE_CONTINUOUS
                   ? talos_rt_v1_native_state_store_continuous_plane
                   : talos_rt_v1_native_state_store_plane;
  uint8_t ignored = 0;
  auto status = read(valuePlane, false, old);
  if (status == TALOS_RT_OK && fourState)
    status = read(unknownPlane, true, oldUnknown);
  if (status == TALOS_RT_OK)
    status = store(context, valuePlane, stateBits, handle, width, 0, input,
                   &ignored);
  if (status == TALOS_RT_OK && fourState)
    status = store(context, unknownPlane, stateBits, handle, width, 1,
                   inputUnknown, &ignored);
  if (status == TALOS_RT_OK)
    status = read(valuePlane, false, next);
  if (status == TALOS_RT_OK && fourState)
    status = read(unknownPlane, true, nextUnknown);
  if (status != TALOS_RT_OK) {
    talos_rt_v1_scheduler_fail(context, status);
    return;
  }
  talos_rt_v1_scheduler_signal_transition(
      context, handle, width, old, fourState ? oldUnknown : nullptr, next,
      fourState ? nextUnknown : nullptr);
}

extern "C" void
talos_rt_v1_native_frame_store(talos_rt_context *context, uint8_t *valuePlane,
                               uint8_t *unknownPlane, uint64_t stateBits,
                               uint64_t handle, uint32_t width, uint32_t flags,
                               uint64_t value, uint64_t unknown) {
  if (!context)
    return;
  if (!width || width > 64 ||
      (flags &
       ~(TALOS_RT_FRAME_STORE_CONTINUOUS | TALOS_RT_FRAME_STORE_UNKNOWN))) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
    return;
  }
  if (handle == UINT64_MAX)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    {
      ContextMutexLock lock(context);
      if (publishFrameStore(context, valuePlane, unknownPlane, stateBits,
                            handle, width, flags, value, unknown)) {
        if (context->signalDiagnosticsEnabled)
          ++context->signalDiagnostics.frameStoresShared;
        return;
      }
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.frameStoreFallbacks;
    }
    uint8_t input[8], inputUnknown[8];
    storePackedWord<uint64_t>(input, value);
    storePackedWord<uint64_t>(inputUnknown, unknown);
    checkedFrameStore<8>(context, valuePlane, unknownPlane, stateBits, handle,
                         width, flags, input, inputUnknown);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_OUT_OF_MEMORY);
  }
  TALOS_RT_CATCH_ALL {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
  }
}

// Capture and publish a multiword blocking assignment as one event (4.6(a),
// 9.4.2). Buffers are in the native packed ABI's little-endian bit order.
extern "C" void talos_rt_v1_native_frame_store_wide(
    talos_rt_context *context, uint8_t *valuePlane, uint8_t *unknownPlane,
    uint64_t stateBits, uint64_t handle, uint32_t width, uint32_t flags,
    const uint8_t *input, const uint8_t *inputUnknown) {
  if (!context || !input || width <= 64 || width > 256 ||
      (flags &
       ~(TALOS_RT_FRAME_STORE_CONTINUOUS | TALOS_RT_FRAME_STORE_UNKNOWN))) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
    return;
  }
  if (handle == UINT64_MAX)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    const bool fourState = flags & TALOS_RT_FRAME_STORE_UNKNOWN;
    uint64_t old[4]{}, oldUnknown[4]{}, next[4]{}, nextUnknown[4]{};
    uint64_t changed[4]{}, rise[4]{}, fall[4]{};
    if (!(flags & TALOS_RT_FRAME_STORE_CONTINUOUS)) {
      ContextMutexLock lock(context);
      auto at = sharedFrameStoreOffset(context, valuePlane, unknownPlane,
                                       stateBits, handle, width, flags);
      if (at && context->forceMask.empty() && context->assignMask.empty()) {
        uint64_t change = 0, hiddenUnknown = 0;
        for (unsigned low = 0; low < width; low += 64) {
          unsigned i = low / 64, count = std::min(64u, width - low);
          uint64_t mask = packedWidthMask(count);
          old[i] = loadPackedBits(context->stateValue, *at + low, count);
          oldUnknown[i] =
              loadPackedBits(context->stateUnknown, *at + low, count);
          if (!fourState)
            hiddenUnknown |= oldUnknown[i];
          next[i] = loadPackedBytes(input, low, count);
          nextUnknown[i] =
              fourState ? loadPackedBytes(inputUnknown, low, count) : 0;
          changed[i] = (old[i] ^ next[i]) | (oldUnknown[i] ^ nextUnknown[i]);
          change |= changed[i];
          uint64_t wasZero = ~old[i] & ~oldUnknown[i],
                   wasOne = old[i] & ~oldUnknown[i];
          uint64_t nowZero = ~next[i] & ~nextUnknown[i],
                   nowOne = next[i] & ~nextUnknown[i];
          rise[i] = ((wasZero & ~nowZero) | (oldUnknown[i] & nowOne)) & mask;
          fall[i] = ((wasOne & ~nowOne) | (oldUnknown[i] & nowZero)) & mask;
        }
        if (!hiddenUnknown) {
          if (context->signalDiagnosticsEnabled)
            ++context->signalDiagnostics.frameStoresShared;
          if (!change)
            return;
          for (unsigned low = 0; low < width; low += 64) {
            unsigned i = low / 64, count = std::min(64u, width - low);
            if (old[i] != next[i])
              storePackedBits(context->stateValue, *at + low, count, next[i]);
            if (oldUnknown[i] != nextUnknown[i]) {
              markNativeUnknownBitsUnlocked(context, *at + low, count,
                                            nextUnknown[i]);
              publishNativeKnownnessChangeUnlocked(
                  context->nativeSchedulePlan, *at + low, count, oldUnknown[i],
                  nextUnknown[i]);
              storePackedBits(context->stateUnknown, *at + low, count,
                              nextUnknown[i]);
            }
          }
          auto bytes = [](const uint64_t *words) {
            return reinterpret_cast<const uint8_t *>(words);
          };
          (void)publishNativeSignalTransitionUnlocked(
              context, handle, width, bytes(changed), bytes(rise), bytes(fall),
              bytes(old), fourState ? bytes(oldUnknown) : nullptr, bytes(next),
              fourState ? bytes(nextUnknown) : nullptr);
          return;
        }
      }
    }
    if (context->signalDiagnosticsEnabled)
      ++context->signalDiagnostics.frameStoreFallbacks;
    uint8_t zero[32]{};
    checkedFrameStore<32>(context, valuePlane, unknownPlane, stateBits, handle,
                          width, flags, input,
                          inputUnknown ? inputUnknown : zero);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_OUT_OF_MEMORY);
  }
  TALOS_RT_CATCH_ALL {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
  }
}

// A periodic edge can have both generated readers and ordinary testbench
// waits. When the live subscriptions cover exactly this one bit, the known
// edge and the armed latches are the complete match (LRM 9.4.2). Validate
// that before publishing anything: an iff, computed event, or other observer
// must see the original publication through the ordinary path.
static bool publishPeriodicDirectWaits(talos_rt_context *context,
                                       uint32_t stateID, uint64_t lowBit,
                                       uint64_t oldValue, uint64_t newValue) {
  const auto *plan = context->nativeSchedulePlan;
  constexpr uint32_t required = TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL |
                                TALOS_RT_NATIVE_SCHEDULE_SHARED_PERIODIC;
  if (!plan || (plan->flags & required) != required || oldValue > 1 ||
      newValue > 1 || lockedNativeAOTContext != context ||
      activeNativeAOTContext != context || context->activeLogicalProcessToken ||
      context->powerNBAs || context->vpiState || context->destroyPending ||
      context->schedulerStatus != TALOS_RT_OK ||
      publicationBatchContext == context ||
      !staticOnlyPublicationEnvironment(context) ||
      !context->forceMask.empty() || !context->assignMask.empty() ||
      !context->stateValue.shared() || !context->stateUnknown.shared() ||
      plan->state_value !=
          reinterpret_cast<const uint8_t *>(context->stateValue.data()) ||
      (plan->state_unknown &&
       plan->state_unknown !=
           reinterpret_cast<const uint8_t *>(context->stateUnknown.data())))
    return false;
  const auto *state = findNativeStaticState(context, stateID);
  const auto *pages = talos_rt_static_signal_bucket_pages(
      context, TALOS_RT_STABLE_HANDLE_STATIC, stateID);
  if (!state || lowBit >= state->bitWidth || !pages || pages->size() != 1 ||
      pages->front().bucket->size() > 64)
    return false;
  uint64_t bit = state->bitOffset + lowBit;
  if (bit >= plan->state_bit_count ||
      loadPackedBits(context->stateValue, bit, 1) != newValue ||
      loadPackedBits(context->stateUnknown, bit, 1) != 0)
    return false;
  uint64_t handle = context->nativePeriodicPublicationHandle;
  const auto &bucket = *pages->front().bucket;
  uint64_t wake = 0;
  for (size_t index = 0; index < bucket.size(); ++index) {
    const auto *sub = bucket[index].subscription;
    if (!sub || sub->target != SignalSubscription::NativeDirectWait ||
        !sub->latch || sub->stableID != handle || sub->bitWidth != 1 ||
        sub->edge > TALOS_RT_WAIT_EDGE_BOTH)
      return false;
    if (!sub->latch->armed || sub->latch->triggered ||
        (sub->edge == TALOS_RT_WAIT_EDGE_POSEDGE && !newValue) ||
        (sub->edge == TALOS_RT_WAIT_EDGE_NEGEDGE && !oldValue))
      continue;
    const auto *process = findScheduledProcess(context, sub->waiterToken);
    if (!process || !process->instance)
      return false;
    if (!sub->outsideStaticFanout &&
        process->aotActorSlot <
            context->nativePeriodicAliasContinuations.size() &&
        context->nativePeriodicAliasContinuations[process->aotActorSlot] ==
            process->instance->continuation)
      continue;
    if (process->aotActorSlot != UINT32_MAX ||
        (!sub->outsideStaticFanout &&
         (plan->flags & TALOS_RT_NATIVE_SCHEDULE_FULLY_STATIC)))
      return false;
    wake |= uint64_t{1} << index;
  }

  // Static fanout owns its sequence. The runtime subscriber walk then owns a
  // separate occurrence, including when every matching latch is already set.
  uint8_t change = 1, posedge = newValue, negedge = oldValue;
  if (!publishStaticAOTSignalTransitionUnlocked(
          context, handle, 1, &change, &posedge, &negedge, nullptr, false))
    return false;
  if (context->schedulerStatus != TALOS_RT_OK)
    return true;
  if (!context->nextSchedulerSequence) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return true;
  }
  uint64_t sequence = context->nextSchedulerSequence++;
  if (context->signalDiagnosticsEnabled)
    ++context->signalDiagnostics.publications;
  for (size_t index = 0; index < bucket.size(); ++index) {
    auto &sub = *bucket[index].subscription;
    if (!sub.latch->armed || sub.lastExaminedSequence == sequence)
      continue;
    sub.lastExaminedSequence = sequence;
    if (context->signalDiagnosticsEnabled)
      ++context->signalDiagnostics.subscribersExamined;
    if ((wake & (uint64_t{1} << index)) && !sub.latch->triggered) {
      sub.latch->triggered = true;
      bool inserted =
          context->nativePollCandidates.insert(sub.waiterToken).second;
      talos_rt_record_native_ready_publication_unlocked(
          context, sub.waiterToken, inserted);
    }
  }
  // Latching an existing wait changes readiness only. The shared planes,
  // overrides, and registrations behind the specialization proof are intact.
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
  return true;
}

// A prepared periodic step stores all its proven scalar copies before its
// Active consumers run (IEEE 1800-2023 4.4.2.2, 4.9.1). The runtime still
// publishes the edge to every other sensitive process, including Observed.
static void publishPeriodicTransition(talos_rt_context *context,
                                      uint32_t staticState, uint64_t lowBit,
                                      uint64_t oldValue, uint64_t newValue,
                                      bool routedOnly) {
  if (!context || oldValue == newValue)
    return;
  ContextMutexLock lock(context);
  struct RestoreHandle {
    uint64_t &handle;
    uint64_t saved;
    ~RestoreHandle() { handle = saved; }
  } restore{context->nativePeriodicPublicationHandle,
            context->nativePeriodicPublicationHandle};
  context->nativePeriodicPublicationHandle = talos_rt_stable_handle_encode(
      TALOS_RT_STABLE_HANDLE_STATIC, staticState, lowBit);
  if (!routedOnly) {
    TALOS_RT_TRY {
      if (publishPeriodicDirectWaits(context, staticState, lowBit, oldValue,
                                     newValue))
        return;
    }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
      return;
    }
    TALOS_RT_CATCH_ALL {
      context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
      return;
    }
  }
  bool delivered = false;
  if (routedOnly && !context->vpiObservationDemand && !context->saif &&
      !context->coverage && !context->clockOccurrences &&
      !context->exactEvents && context->stateValue.shared() &&
      context->signalValueSnapshots.empty() && context->forceMask.empty() &&
      context->assignMask.empty() &&
      nativeStaticSpecializationEnvironmentClean(context)) {
    // This clock has only exact runtime fanout entries. The projected clock
    // has already updated the shared image. No computed predicate observes
    // its intermediate publication (1800-2023 4.4.2, 9.4.2).
    uint8_t changed = 1, posedge = newValue != 0, negedge = oldValue != 0;
    delivered = publishStaticAOTSignalTransitionUnlockedImpl<false, true>(
        context, context->nativePeriodicPublicationHandle, 1, &changed,
        &posedge, &negedge, nullptr, false);
    if (delivered && ++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
  }
  if (!delivered)
    talos_rt_v1_scheduler_static_transition(context, staticState, lowBit, 1,
                                            oldValue, 0, newValue, 0);
}

extern "C" void talos_rt_v1_scheduler_periodic_transition(
    talos_rt_context *context, uint32_t staticState, uint64_t lowBit,
    uint64_t oldValue, uint64_t newValue) {
  publishPeriodicTransition(context, staticState, lowBit, oldValue, newValue,
                            false);
}

extern "C" void talos_rt_v1_scheduler_periodic_routed_transition(
    talos_rt_context *context, uint32_t staticState, uint64_t lowBit,
    uint64_t oldValue, uint64_t newValue) {
  publishPeriodicTransition(context, staticState, lowBit, oldValue, newValue,
                            true);
}

static void schedulerStaticTransition(talos_rt_context *context,
                                      uint32_t staticState, uint64_t lowBit,
                                      uint64_t bitWidth, uint64_t oldValue,
                                      uint64_t oldUnknown, uint64_t newValue,
                                      uint64_t newUnknown,
                                      bool generatedIngress) {
  if (!context || staticState == 0 || bitWidth == 0 || bitWidth > 64)
    return;
  uint64_t widthMask = packedWidthMask(bitWidth);
  oldValue &= widthMask;
  oldUnknown &= widthMask;
  newValue &= widthMask;
  newUnknown &= widthMask;
  uint64_t changed = (oldValue ^ newValue) | (oldUnknown ^ newUnknown);
  if (changed == 0)
    return;

  // A merging publication batch holds the transitions it proved take the
  // ordinary path below. The generated AOT leaf publishes differently (an
  // eval island has already raised its own ingress), so it is never held; it
  // follows the held writes.
  if (publicationBatchContext == context) {
    if (deferBatchedStaticTransition(context, staticState, lowBit, bitWidth,
                                     oldValue, oldUnknown, newValue, newUnknown,
                                     changed))
      return;
    flushPublicationBatch(context);
  }

  const auto *plan =
      lockedNativeAOTContext == context && activeNativeAOTContext == context
          ? context->nativeSchedulePlan
          : nullptr;
  bool lockedCalendar =
      plan && lowBit <= INT32_MAX &&
      (plan->flags & TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL) &&
      !context->nativeStaticEvalIslandCertified && !context->destroyPending &&
      context->schedulerStatus == TALOS_RT_OK &&
      publicationBatchContext != context;
  const NativeStaticState *state =
      lockedCalendar ? findNativeStaticState(context, staticState) : nullptr;
  lockedCalendar = state && lowBit <= state->bitWidth &&
                   bitWidth <= state->bitWidth - lowBit;
  // A mid-slot handover remains correct by entering the ordinary transition
  // path with the same scalar planes.
  if (!lockedCalendar && staticTransitionTakesOrdinaryPath(context)) {
    uint64_t handle = talos_rt_stable_handle_encode(
        TALOS_RT_STABLE_HANDLE_STATIC, staticState,
        static_cast<int64_t>(lowBit));
    talos_rt_v1_scheduler_signal_transition(
        context, handle, bitWidth, reinterpret_cast<const uint8_t *>(&oldValue),
        reinterpret_cast<const uint8_t *>(&oldUnknown),
        reinterpret_cast<const uint8_t *>(&newValue),
        reinterpret_cast<const uint8_t *>(&newUnknown));
    return;
  }
  if (!state)
    state = findNativeStaticState(context, staticState);
  if (!state || lowBit > state->bitWidth ||
      bitWidth > state->bitWidth - lowBit) {
    context->schedulerStatus = TALOS_RT_LAYOUT_MISMATCH;
    return;
  }
  uint64_t handle = talos_rt_stable_handle_encode(
      TALOS_RT_STABLE_HANDLE_STATIC, staticState, static_cast<int64_t>(lowBit));
  if (lockedCalendar || ((context->nativeSchedulePlan->flags &
                          TALOS_RT_NATIVE_SCHEDULE_STATIC_EVAL_ISLAND) &&
                         (context->nativeSchedulePlan->flags &
                          TALOS_RT_NATIVE_SCHEDULE_RUNTIME_CALENDAR_EVAL))) {
    // Generated ingress is already published, but retained transitions also
    // feed runtime-owned waiters. Preserve the source-order canonical image
    // and notify those subscribers before the calendar can advance (9.4.2,
    // 31.9.1). Native subscribers route to idempotent generated ingress.
    uint64_t oldZero = ~oldUnknown & ~oldValue & widthMask;
    uint64_t oldOne = ~oldUnknown & oldValue & widthMask;
    uint64_t newZero = ~newUnknown & ~newValue & widthMask;
    uint64_t newOne = ~newUnknown & newValue & widthMask;
    uint64_t posedge =
        ((oldZero & ~newZero) | (oldUnknown & newOne)) & widthMask;
    uint64_t negedge =
        ((oldOne & ~newOne) | (oldUnknown & newZero)) & widthMask;
    // The bounded values already are the scalar transition the ordinary ABI
    // would reconstruct from byte arrays. Keep its complete publication,
    // including occurrence callbacks, canonical-plane updates and overrides.
    ContextTransaction transaction(context);
    TALOS_RT_TRY {
      (void)publishNativeSignalTransitionUnlocked(
          context, handle, bitWidth,
          reinterpret_cast<const uint8_t *>(&changed),
          reinterpret_cast<const uint8_t *>(&posedge),
          reinterpret_cast<const uint8_t *>(&negedge),
          reinterpret_cast<const uint8_t *>(&oldValue),
          reinterpret_cast<const uint8_t *>(&oldUnknown),
          reinterpret_cast<const uint8_t *>(&newValue),
          reinterpret_cast<const uint8_t *>(&newUnknown), false,
          generatedIngress);
    }
    TALOS_RT_CATCH(const std::bad_alloc &) {
      talos_rt_v1_scheduler_fail(context, TALOS_RT_OUT_OF_MEMORY);
    }
    TALOS_RT_CATCH_ALL {
      talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
    }
    return;
  }
  if (context->coverage)
    talos_rt_coverage_record_transition_unlocked(
        context, handle, bitWidth, reinterpret_cast<const uint8_t *>(&changed),
        reinterpret_cast<const uint8_t *>(&newValue),
        reinterpret_cast<const uint8_t *>(&newUnknown));
  if (context->saif)
    talos_rt_saif_record_transition_unlocked(
        context, handle, bitWidth, reinterpret_cast<const uint8_t *>(&changed),
        reinterpret_cast<const uint8_t *>(&newValue),
        reinterpret_cast<const uint8_t *>(&newUnknown));
  uint8_t edgeKinds = 0;
  if (staticState < context->nativeScheduleStaticStateFanoutEdges.size()) {
    edgeKinds = context->nativeScheduleStaticStateFanoutEdges[staticState];
  }
  uint8_t posedgeKinds = (uint8_t{1} << TALOS_RT_WAIT_EDGE_POSEDGE) |
                         (uint8_t{1} << TALOS_RT_WAIT_EDGE_BOTH);
  uint8_t negedgeKinds = (uint8_t{1} << TALOS_RT_WAIT_EDGE_NEGEDGE) |
                         (uint8_t{1} << TALOS_RT_WAIT_EDGE_BOTH);
  uint64_t posedge = 0;
  uint64_t negedge = 0;
  if (context->exactEvents ||
      (edgeKinds & (posedgeKinds | negedgeKinds)) != 0) {
    uint64_t oldZero = ~oldUnknown & ~oldValue & widthMask;
    uint64_t oldOne = ~oldUnknown & oldValue & widthMask;
    uint64_t newZero = ~newUnknown & ~newValue & widthMask;
    uint64_t newOne = ~newUnknown & newValue & widthMask;
    if (context->exactEvents || (edgeKinds & posedgeKinds) != 0)
      posedge = ((oldZero & ~newZero) | (oldUnknown & newOne)) & widthMask;
    if (context->exactEvents || (edgeKinds & negedgeKinds) != 0)
      negedge = ((oldOne & ~newOne) | (oldUnknown & newZero)) & widthMask;
  }
  if (context->exactEvents &&
      !publishCovergroupClockTransitionUnlocked(
          context, handle, bitWidth,
          reinterpret_cast<const uint8_t *>(&changed),
          reinterpret_cast<const uint8_t *>(&posedge),
          reinterpret_cast<const uint8_t *>(&negedge),
          reinterpret_cast<const uint8_t *>(&newValue),
          reinterpret_cast<const uint8_t *>(&newUnknown)))
    return;
  // Generated Eval bodies publish their statically indexed actor ingress
  // locally. The retained v1 callback exists only for runtime-owned observers
  // such as covergroup clock events; do not enqueue the same native fanout a
  // second time through the runtime plan.
  if ((context->nativeSchedulePlan->flags &
       TALOS_RT_NATIVE_SCHEDULE_STATIC_EVAL_ISLAND) != 0) {
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
    return;
  }
  if (edgeKinds == 0) {
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
    return;
  }
  uint64_t observedEdges = 0;
  if ((edgeKinds & (uint8_t{1} << TALOS_RT_WAIT_EDGE_CHANGE)) != 0)
    observedEdges |= changed;
  if ((edgeKinds & posedgeKinds) != 0)
    observedEdges |= posedge;
  if ((edgeKinds & negedgeKinds) != 0)
    observedEdges |= negedge;
  if (observedEdges == 0) {
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
    return;
  }

  const talos_rt_static_fanout_entry *begin =
      context->nativeScheduleFanoutEntries;
  const talos_rt_static_fanout_entry *end =
      begin + context->nativeScheduleFanoutEntryCount;
  auto first = end;
  auto last = end;
  if (staticState < context->nativeScheduleFanoutRanges.size()) {
    auto [firstIndex, lastIndex] =
        context->nativeScheduleFanoutRanges[staticState];
    if (firstIndex <= lastIndex &&
        lastIndex <= context->nativeScheduleFanoutEntryCount) {
      first = begin + firstIndex;
      last = begin + lastIndex;
    }
  } else {
    first =
        std::lower_bound(begin, end, staticState,
                         [](const talos_rt_static_fanout_entry &entry,
                            uint32_t id) { return entry.static_state < id; });
    last = first;
    while (last != end && last->static_state == staticState)
      ++last;
  }
  bool published = false;
  uint64_t publishedEnd = lowBit + bitWidth;
  for (auto entry = first; entry != last; ++entry) {
    ++context->signalDiagnostics.aotFanoutEntries;
    uint64_t overlapLow = std::max(lowBit, entry->low_bit);
    uint64_t overlapHigh =
        std::min(publishedEnd, entry->low_bit + entry->bit_width);
    if (overlapLow >= overlapHigh)
      continue;
    uint64_t localLow = overlapLow - lowBit;
    uint64_t localWidth = overlapHigh - overlapLow;
    uint64_t overlapMask = packedWidthMask(localWidth)
                           << static_cast<unsigned>(localLow);
    uint64_t observed = changed;
    switch (entry->edge) {
    case TALOS_RT_WAIT_EDGE_POSEDGE:
      observed = posedge;
      break;
    case TALOS_RT_WAIT_EDGE_NEGEDGE:
      observed = negedge;
      break;
    case TALOS_RT_WAIT_EDGE_BOTH:
      observed = posedge | negedge;
      break;
    default:
      break;
    }
    if ((observed & overlapMask) == 0)
      continue;

    uint32_t slot = entry->actor_slot;
    if (slot >= context->nativeScheduleActors.size()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    talos_rt_process_instance_v1 *actor = context->nativeScheduleActors[slot];
    if (!actor)
      continue;
    size_t index = context->nativeScheduleActorIndices[slot];
    if (index >= context->scheduledProcesses.size()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    ScheduledProcess &scheduled = context->scheduledProcesses[index];
    bool activeSelf = context->activeLogicalProcessToken ==
                      (kNativeLogicalProcessTag | scheduled.token);
    if (activeSelf &&
        (entry->reserved & TALOS_RT_FANOUT_SUPPRESS_ACTIVE_SELF) != 0)
      continue;
    if ((actor->continuation != entry->continuation && !activeSelf) ||
        scheduled.instance != actor || !scheduled.started ||
        (scheduled.signalTriggered && !activeSelf) ||
        (scheduled.suspendKind != TALOS_RT_SUSPEND_CHANGE &&
         scheduled.suspendKind != TALOS_RT_SUSPEND_EDGE))
      continue;
    if (!published) {
      if (context->nextSchedulerSequence == 0) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return;
      }
      ++context->nextSchedulerSequence;
      if (context->signalDiagnosticsEnabled)
        ++context->signalDiagnostics.publications;
      published = true;
    }
    // A generated owner's wake is its generated ready bit whoever writes, as
    // for any other runtime publication: the coordinator runs the owner, not
    // its process body, at the scheduler's next iteration (Active events in
    // any order, IEEE 1800-2023 4.7) and stops at its cuts while runtime
    // work below them remains (4.4.2.3, 4.4.2.4, 4.5). A pending bit (for
    // example the owner's time-zero activation) absorbs the wake: an owner
    // that has not run yet is not waiting at its event control (9.2.2.2,
    // 9.4.2).
    if ((context->nativeSchedulePlan->flags & TALOS_RT_NATIVE_SCHEDULE_EVAL) &&
        (entry->reserved & TALOS_RT_FANOUT_ROUTE_MASK) ==
            TALOS_RT_FANOUT_DIRECT &&
        entry->kernel < context->nativeSchedulePlan->clock_kernel_count) {
      const talos_rt_native_clock_kernel &kernel =
          context->nativeSchedulePlan->clock_kernels[entry->kernel];
      if (entry->merged_bit / 64 >= kernel.ingress_word_count) {
        context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
        return;
      }
      talos::runtime::publishClockKernelReady(kernel, entry->merged_bit);
      context->nativeScheduleClockIngressPending = true;
      continue;
    }
    if (context->saif && !scheduled.signalTriggered)
      talos_rt_saif_wake_unlocked(context, TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG |
                                               scheduled.token);
    scheduled.signalTriggered = true;
    uint32_t node = entry->compute_node;
    if (node >= context->nativeScheduleNodes.size() ||
        node >= context->nativeScheduleReadyNodes.capacity()) {
      context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
      return;
    }
    context->nativeScheduleReadyNodes.set(node);
    context->nativePollCandidates.insert(scheduled.token);
    if (++context->schedulerSelectionGeneration == 0)
      context->schedulerSelectionGeneration = 1;
    context->nativeScheduleMinimumActivatedNode =
        std::min(context->nativeScheduleMinimumActivatedNode, node);
  }
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
}

extern "C" void talos_rt_v1_scheduler_static_transition(
    talos_rt_context *context, uint32_t staticState, uint64_t lowBit,
    uint64_t bitWidth, uint64_t oldValue, uint64_t oldUnknown,
    uint64_t newValue, uint64_t newUnknown) {
  schedulerStaticTransition(context, staticState, lowBit, bitWidth, oldValue,
                            oldUnknown, newValue, newUnknown, false);
}

extern "C" void talos_rt_v1_scheduler_static_transition_projected(
    talos_rt_context *context, uint32_t actorSlot, uint32_t staticState,
    uint64_t lowBit, uint64_t bitWidth, uint64_t oldValue, uint64_t oldUnknown,
    uint64_t newValue, uint64_t newUnknown) {
  publishAsNativeActor(context, actorSlot, [&] {
    schedulerStaticTransition(context, staticState, lowBit, bitWidth, oldValue,
                              oldUnknown, newValue, newUnknown, true);
  });
}

extern "C" void talos_rt_v1_scheduler_wide_transition_projected(
    talos_rt_context *context, uint32_t actorSlot, uint64_t handle,
    uint64_t width, const uint8_t *oldValue, const uint8_t *oldUnknown,
    const uint8_t *newValue, const uint8_t *newUnknown) {
  publishAsNativeActor(context, actorSlot, [&] {
    schedulerSignalTransition(context, handle, width, oldValue, oldUnknown,
                              newValue, newUnknown, false, true);
  });
}

extern "C" void talos_rt_v1_scheduler_activate_static_nodes(
    talos_rt_context *context, const uint64_t *nodeWords, uint32_t wordCount) {
  if (!context || !nodeWords)
    return;
  if (!context->nativeSchedulePlan ||
      wordCount != context->nativeScheduleReadyNodes.wordCount()) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return;
  }
  bool hasNodes = false;
  for (uint32_t word = 0; word != wordCount; ++word)
    hasNodes |= nodeWords[word] != 0;
  if (!hasNodes)
    return;
  // The generated NBA barrier computes these wakes with exact edge tests on
  // the values it commits (IEEE 1800-2023 9.4.2, 10.4.2). Inside the generated
  // plan they are node wakes of the runtime-driven node loop even before the
  // eval island is certified: certification governs exclusive calendar
  // ownership, not ready nodes, and the checks below still require each actor
  // to wait at that continuation.
  bool generatedPlan = activeNativeAOTContext == context &&
                       !context->nativeScheduleDeoptimized;
  bool indexedExternal = canUseIndexedExternalAOTFanout(context);
  bool usable = generatedPlan ||
                ((activeNativeAOTContext == context || indexedExternal) &&
                 (canUseStaticAOTFanout(context) || indexedExternal));
  if (!usable ||
      (context->nativeSchedulePlan->flags &
       (TALOS_RT_NATIVE_SCHEDULE_CLEAN_SUPERSTEP |
        TALOS_RT_NATIVE_SCHEDULE_STATIC_EVAL_ISLAND)) == 0 ||
      context->nativeScheduleReadyNodes.wordCount() == 0) {
    context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
    return;
  }

  bool published = false;
  for (uint32_t word = 0; word != wordCount; ++word) {
    uint64_t nodes = nodeWords[word];
    while (nodes != 0) {
      uint32_t bit = static_cast<uint32_t>(__builtin_ctzll(nodes));
      uint32_t node = word * 64 + bit;
      nodes &= nodes - 1;
      if (node >= context->nativeScheduleNodes.size()) {
        context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
        return;
      }
      const talos_rt_native_schedule_node &entry =
          context->nativeScheduleNodes[node];
      if (entry.actor_slot >= context->nativeScheduleActors.size()) {
        context->schedulerStatus = TALOS_RT_INVALID_CONTINUATION;
        return;
      }
      talos_rt_process_instance_v1 *actor =
          context->nativeScheduleActors[entry.actor_slot];
      if (!actor)
        continue;
      size_t index = context->nativeScheduleActorIndices[entry.actor_slot];
      if (index >= context->scheduledProcesses.size()) {
        context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
        return;
      }
      ScheduledProcess &scheduled = context->scheduledProcesses[index];
      bool activeSelf = context->activeLogicalProcessToken ==
                        (kNativeLogicalProcessTag | scheduled.token);
      if ((actor->continuation != entry.continuation && !activeSelf) ||
          scheduled.instance != actor || !scheduled.started ||
          (scheduled.signalTriggered && !activeSelf) ||
          (scheduled.suspendKind != TALOS_RT_SUSPEND_CHANGE &&
           scheduled.suspendKind != TALOS_RT_SUSPEND_EDGE))
        continue;
      if (context->saif && !scheduled.signalTriggered)
        talos_rt_saif_wake_unlocked(
            context, TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG | scheduled.token);
      scheduled.signalTriggered = true;
      context->nativeScheduleReadyNodes.set(node);
      context->nativePollCandidates.insert(scheduled.token);
      if (++context->schedulerSelectionGeneration == 0)
        context->schedulerSelectionGeneration = 1;
      context->nativeScheduleMinimumActivatedNode =
          std::min(context->nativeScheduleMinimumActivatedNode, node);
      ++context->signalDiagnostics.aotFanoutEntries;
      published = true;
    }
  }
  if (!published)
    return;
  if (context->nextSchedulerSequence == 0) {
    context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
    return;
  }
  ++context->nextSchedulerSequence;
  if (context->signalDiagnosticsEnabled)
    ++context->signalDiagnostics.publications;
  if (++context->schedulerEpoch == 0)
    context->schedulerEpoch = 1;
}

static void commitRealToCanonicalPlaneUnlocked(talos_rt_context *context,
                                               uint64_t bitOffset,
                                               uint32_t bitWidth,
                                               uint64_t newBits) {
  if (context->stateValue.shared())
    return;
  uint32_t staticID = 0;
  int64_t offset = 0;
  uint64_t absolute = 0;
  if (decodeNativeStatic(bitOffset, staticID, offset)) {
    const NativeStaticState *state = findNativeStaticState(context, staticID);
    if (!state || offset < 0 ||
        static_cast<uint64_t>(offset) + bitWidth > state->bitWidth)
      return;
    absolute = state->bitOffset + static_cast<uint64_t>(offset);
  } else if (decodeNativeGlobal(bitOffset, offset) && offset >= 0) {
    absolute = static_cast<uint64_t>(offset);
  } else {
    return;
  }
  uint64_t size = context->stateValue.size() * uint64_t{64};
  if (absolute + bitWidth > size ||
      absolute + bitWidth > context->stateUnknown.size() * uint64_t{64})
    return;
  // IEEE 1800-2023 10.6.2: an overridden target keeps the override's value.
  if (nativeMaskIntersectsRange(context->forceMask, absolute, bitWidth) ||
      nativeMaskIntersectsRange(context->assignMask, absolute, bitWidth))
    return;
  storePackedBits(context->stateValue, absolute, bitWidth, newBits);
  storePackedBits(context->stateUnknown, absolute, bitWidth, 0);
}

extern "C" void talos_rt_v1_scheduler_real_transition(talos_rt_context *context,
                                                      uint64_t bitOffset,
                                                      uint32_t bitWidth,
                                                      const void *oldValue,
                                                      const void *newValue) {
  if (!context || bitOffset == UINT64_MAX ||
      (bitWidth != 32 && bitWidth != 64) || !oldValue || !newValue)
    return;
  // A guarded generated store reaches only its own plane, and observers read
  // the canonical one, so advance that as the integer publication path does.
  // Bits are compared because -0.0 and 0.0 are no value change but are
  // different values.
  uint64_t oldBits = 0;
  uint64_t newBits = 0;
  std::memcpy(&oldBits, oldValue, bitWidth / 8);
  std::memcpy(&newBits, newValue, bitWidth / 8);
  if (oldBits != newBits) {
    ContextMutexLock lock(context);
    commitRealToCanonicalPlaneUnlocked(context, bitOffset, bitWidth, newBits);
  }
  bool changed = false;
  if (bitWidth == 32) {
    float oldReal = 0.0f;
    float newReal = 0.0f;
    std::memcpy(&oldReal, oldValue, sizeof(oldReal));
    std::memcpy(&newReal, newValue, sizeof(newReal));
    changed = oldReal != newReal || std::isnan(newReal);
  } else {
    double oldReal = 0.0;
    double newReal = 0.0;
    std::memcpy(&oldReal, oldValue, sizeof(oldReal));
    std::memcpy(&newReal, newValue, sizeof(newReal));
    changed = oldReal != newReal || std::isnan(newReal);
  }
  if (!changed)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return;
    if (!talos_rt_publish_signal_occurrence_unlocked(
            context, bitOffset, bitWidth, TALOS_RT_SIGNAL_CHANGE))
      return;
    talos_rt_invalidate_signal_snapshots_unlocked(context, bitOffset, bitWidth);
    if (!talos_rt_latch_conditional_signal_range_unlocked(
            context, bitOffset, bitWidth, TALOS_RT_SIGNAL_CHANGE))
      return;
    if (!talos_rt_notify_observer_signal_unlocked(context, bitOffset, bitWidth))
      return;
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
  }
  TALOS_RT_CATCH_ALL {
    talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
  }
}

extern "C" void talos_rt_v1_scheduler_event(talos_rt_context *context,
                                            uint64_t stableID,
                                            uint32_t nonblocking) {
  talos_rt_v1_scheduler_event_after(context, stableID, nonblocking, 0);
}

extern "C" talos_rt_status
talos_rt_v1_scheduler_event_create(talos_rt_context *context,
                                   uint64_t *outStableID) {
  if (!context || !outStableID)
    return TALOS_RT_INVALID_ARGUMENT;
  *outStableID = UINT64_MAX;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return context->schedulerStatus;
    if (context->nextDynamicEventID == 0 ||
        context->nextDynamicEventID >= TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG)
      return TALOS_RT_OUT_OF_RESOURCES;
    *outStableID = TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG |
                   context->nextDynamicEventID++;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_ARGUMENT; }
}

extern "C" void talos_rt_v1_scheduler_event_after(talos_rt_context *context,
                                                  uint64_t stableID,
                                                  uint32_t nonblocking,
                                                  uint64_t delay) {
  if (!context || nonblocking > 1 || (!nonblocking && delay != 0)) {
    if (context)
      talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
    return;
  }
  // IEEE 1800-2017 15.5.5.2: triggering a null event has no effect. The
  // all-ones stable ID is the canonical null event in native execution; do
  // not create its queue or enqueue a delayed/nonblocking occurrence.
  if (stableID == UINT64_MAX)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return;
    if (context->activeExecRegion == TALOS_RT_REGION_POSTPONED) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    uint32_t retainedAutomaticID = 0;
    int64_t automaticOffset = 0;
    if (decodeNativeAutomatic(stableID, retainedAutomaticID, automaticOffset)) {
      auto found = context->nativeAutomaticStates.find(retainedAutomaticID);
      if (found == context->nativeAutomaticStates.end()) {
        context->schedulerStatus = TALOS_RT_INVALID_HANDLE;
        return;
      }
      if (nonblocking && found->second.referenceCount == UINT64_MAX) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return;
      }
    }
    if (nonblocking) {
      if (context->nextSchedulerSequence == 0) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return;
      }
      uint64_t dueTime = delay > UINT64_MAX - context->schedulerTime
                             ? UINT64_MAX
                             : context->schedulerTime + delay;
      uint32_t execRegion = talos_rt_commit_region(
          context->activeHomeRegion == UINT32_MAX
              ? static_cast<uint32_t>(TALOS_RT_REGION_ACTIVE)
              : context->activeHomeRegion);
      if (execRegion == UINT32_MAX) {
        context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
        return;
      }
      context->scheduledDesignEvents.push_back({context->nextSchedulerSequence,
                                                dueTime, execRegion, stableID,
                                                retainedAutomaticID});
      if (retainedAutomaticID != 0)
        ++context->nativeAutomaticStates.find(retainedAutomaticID)
              ->second.referenceCount;
      ++context->nextSchedulerSequence;
      return;
    }
    EventState &event = context->events[stableID];
    if (++event.generation == 0)
      event.generation = 1;
    event.lastTriggeredTime = context->schedulerTime;
    if (!talos_rt_notify_event_order_waiters_unlocked(context, stableID))
      return;
    if (!talos_rt_notify_observer_event_unlocked(context, stableID))
      return;
    if (++context->schedulerEpoch == 0)
      context->schedulerEpoch = 1;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
  }
  TALOS_RT_CATCH_ALL {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
  }
}

extern "C" void
talos_rt_v1_scheduler_event_replace_after(talos_rt_context *context,
                                          uint64_t stableID, uint32_t active,
                                          uint64_t delay) {
  if (!context || active > 1) {
    if (context)
      talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_ARGUMENT);
    return;
  }
  // A null named event is inert for cancellation as well as triggering
  // (IEEE 1800-2017 15.5.5.2).
  if (stableID == UINT64_MAX)
    return;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    if (context->schedulerStatus != TALOS_RT_OK)
      return;
    if (!context->clockOccurrences) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    ClockOccurrenceFeatureState &clock = *context->clockOccurrences;
    uint64_t ownerToken = context->activeLogicalProcessToken;
    if (ownerToken == 0 || clock.waits.find(ownerToken) == clock.waits.end()) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    if (!clock.replaceableEvents) {
      if (!active)
        return;
      clock.replaceableEvents =
          std::make_unique<ReplaceableEventFeatureState>();
    }
    ReplaceableEventFeatureState &feature = *clock.replaceableEvents;
    auto foundPending = feature.pending.find(stableID);
    if (foundPending != feature.pending.end() &&
        foundPending->second.ownerToken != ownerToken) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return;
    }
    if (foundPending == feature.pending.end()) {
      auto [owned, insertedOwner] = feature.ownedTimers.try_emplace(ownerToken);
      size_t priorOwnedSize = owned->second.size();
      TALOS_RT_TRY {
        owned->second.push_back(stableID);
        auto [inserted, success] = feature.pending.try_emplace(stableID);
        if (!success) {
          owned->second.pop_back();
          if (insertedOwner && owned->second.empty())
            feature.ownedTimers.erase(owned);
          context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
          return;
        }
        inserted->second.ownerToken = ownerToken;
        foundPending = inserted;
      }
      TALOS_RT_CATCH_ALL {
        if (owned->second.size() != priorOwnedSize)
          owned->second.resize(priorOwnedSize);
        if (insertedOwner && owned->second.empty())
          feature.ownedTimers.erase(owned);
        TALOS_RT_RETHROW;
      }
    }
    ReplaceableEventPending &pending = foundPending->second;
    // The generation is a permanent guard, not a wrapping stale-event tag.
    // Once exhausted, no later replacement may accidentally make an ancient
    // maturity current again.
    if (pending.generation == UINT64_MAX ||
        (active && context->nextSchedulerSequence == 0)) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return;
    }
    ++pending.generation;
    if (pending.scheduled) {
      feature.calendar.erase(pending.event);
      pending.scheduled = false;
    }
    if (!active)
      return;

    // Match ordinary delayed named-event saturation exactly. UINT64_MAX is a
    // permanent deadline/sentinel and must never wrap into an early expiry.
    uint64_t dueTime = delay > UINT64_MAX - context->schedulerTime
                           ? UINT64_MAX
                           : context->schedulerTime + delay;
    uint64_t sequence = context->nextSchedulerSequence++;
    auto [event, inserted] = feature.calendar.emplace(
        std::pair{dueTime, sequence},
        ScheduledDesignEvent{sequence, dueTime, TALOS_RT_REGION_RE_NBA,
                             stableID, 0});
    if (!inserted) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return;
    }
    pending.event = event;
    pending.scheduled = true;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
  }
  TALOS_RT_CATCH_ALL {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
  }
}

extern "C" uint32_t
talos_rt_v1_scheduler_event_triggered(talos_rt_context *context,
                                      uint64_t stableID) {
  if (!context)
    return 0;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    auto found = context->events.find(stableID);
    return found != context->events.end() && found->second.generation != 0 &&
           found->second.lastTriggeredTime == context->schedulerTime;
  }
  TALOS_RT_CATCH_ALL { return 0; }
}

extern "C" uint32_t
talos_rt_v1_scheduler_wait_order_failed(talos_rt_context *context) {
  if (!context)
    return 0;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    return context->activeLogicalProcessToken != 0 &&
           context->activeWaitOrderFailed;
  }
  TALOS_RT_CATCH_ALL { return 0; }
}

extern "C" uint64_t
talos_rt_v1_clock_occurrence_consume(talos_rt_context *context,
                                     uint64_t occurrenceSite) {
  if (!context || occurrenceSite == 0)
    return 0;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    uint64_t token = context->activeLogicalProcessToken;
    if (token == 0 || !context->clockOccurrences)
      return 0;
    auto found = context->clockOccurrences->waits.find(token);
    if (found == context->clockOccurrences->waits.end() ||
        found->second.occurrenceSite != occurrenceSite)
      return 0;
    ClockOccurrenceWaitState &state = found->second;
    if (state.consumedCohorts == state.finalizedCohorts.size() &&
        state.hasCurrentKey) {
      ClockOccurrenceWaveKey active{context->schedulerTime,
                                    context->schedulerSlotProgress,
                                    context->activeExecRegion};
      // The producer fragment or barrier must return before its mask is
      // visible. Until then another publication can still join this exact
      // wave, so an early consume observes no partial cohort.
      if (!(state.currentKey == active))
        finalizeClockOccurrenceWave(state);
    }
    if (state.consumedCohorts == state.finalizedCohorts.size())
      return 0;
    uint64_t result = state.finalizedCohorts[state.consumedCohorts++];
    if (state.consumedCohorts == state.finalizedCohorts.size()) {
      state.finalizedCohorts.clear();
      state.consumedCohorts = 0;
    } else if (state.consumedCohorts >= 1024 &&
               state.consumedCohorts * 2 >= state.finalizedCohorts.size()) {
      state.finalizedCohorts.erase(state.finalizedCohorts.begin(),
                                   state.finalizedCohorts.begin() +
                                       state.consumedCohorts);
      state.consumedCohorts = 0;
    }
    return result;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
    return 0;
  }
  TALOS_RT_CATCH_ALL {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
    return 0;
  }
}

extern "C" uint64_t talos_rt_v1_nochange_update(talos_rt_context *context,
                                                uint64_t occurrenceSite,
                                                uint64_t occurrenceMask,
                                                int64_t startOffset,
                                                int64_t endOffset) {
  if (!context || occurrenceSite == 0 || (occurrenceMask & ~uint64_t{7}) != 0)
    return 0;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    uint64_t token = context->activeLogicalProcessToken;
    if (token == 0 || !context->clockOccurrences) {
      context->schedulerStatus = TALOS_RT_INVALID_LIFECYCLE;
      return 0;
    }
    if (!context->noChangeChecks)
      context->noChangeChecks = std::make_unique<NoChangeFeatureState>();
    NoChangeCheckState &state =
        context->noChangeChecks->checks[{token, occurrenceSite}];
    if (!state.initialized) {
      state.startOffset = startOffset;
      state.endOffset = endOffset;
      state.initialized = true;
    } else if (state.startOffset != startOffset ||
               state.endOffset != endOffset) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return 0;
    }

    if (occurrenceMask == 0) {
      if (!finalizeNoChangeOpenWindow(context, state))
        return 0;
      uint64_t reports = state.pendingReports;
      state.pendingReports = 0;
      pruneNoChangeData(state, context->schedulerTime);
      return reports;
    }

    uint64_t now = context->schedulerTime;
    state.windows.erase(
        std::remove_if(state.windows.begin(), state.windows.end(),
                       [&](const NoChangeClosedWindow &window) {
                         return window.end <= static_cast<__int128>(now);
                       }),
        state.windows.end());

    // IEEE 1800-2017 31.4.6 defines strict numeric-time endpoints. Ordered
    // clock cohorts are retained for repeated derived edges, but data at the
    // same time is independent of within-cohort processing order: history
    // makes a later leading/trailing occurrence see it retroactively.
    if ((occurrenceMask & 2) != 0 && !recordNoChangeData(context, state, now))
      return 0;
    if ((occurrenceMask & 1) != 0) {
      state.openBegin = static_cast<__int128>(now) - startOffset;
      state.openDataBegin = state.dataBegin;
      state.open = true;
    }
    if ((occurrenceMask & 4) != 0 && !closeNoChangeWindow(context, state, now))
      return 0;
    pruneNoChangeData(state, now);
    return 0;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
    return 0;
  }
  TALOS_RT_CATCH_ALL {
    ContextMutexLock lock(context);
    context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT;
    return 0;
  }
}
