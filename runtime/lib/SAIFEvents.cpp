//===- SAIFEvents.cpp - Event-owned causal state across scheduler tiers ---===//
#include "DesignBytecodeNets.h"
#include "ProcessContext.h"
#include "ProcessPacking.h"
#include "ProcessShared.h"
#include "SAIFInternal.h"
using namespace talos::saifruntime;
namespace {
struct Frame {
  talos_rt_context *context = nullptr;
  std::shared_ptr<const SAIFCause> cause;
  uint64_t logical = 0;
};
thread_local Frame active;
thread_local std::vector<Frame> directFrames;
std::shared_ptr<const SAIFCause> fresh(talos_rt_context *) {
  return std::make_shared<SAIFCause>();
}
void enter(talos_rt_context *context, uint64_t logical) {
  auto &state = *context->saif;
  auto queued = state.wakeups.find(logical);
  auto resumed = state.resumptions.find(logical);
  auto cause = queued != state.wakeups.end() ? queued->second
               : active.context == context && active.logical == logical
                   ? active.cause
               : resumed != state.resumptions.end() ? resumed->second
                                                    : fresh(context);
  if (queued != state.wakeups.end()) {
    state.resumptions[logical] = cause;
    state.wakeups.erase(queued);
  }
  active = {context, std::move(cause), logical};
  state.activeLogical = logical;
  state.publicationCause = active.cause;
}
} // namespace
std::shared_ptr<const SAIFCause>
talos_rt_saif_current_cause_unlocked(talos_rt_context *context) {
  return active.context == context ? active.cause
                                   : std::shared_ptr<const SAIFCause>{};
}
std::shared_ptr<const SAIFCause>
talos_rt_saif_capture_cause_unlocked(talos_rt_context *context) {
  auto cause = talos_rt_saif_current_cause_unlocked(context);
  if (cause)
    return cause;
  if (context->saif->publicationCause)
    return context->saif->publicationCause;
  return fresh(context);
}
void talos_rt_saif_wake_unlocked(talos_rt_context *context, uint64_t logical) {
  auto &state = *context->saif;
  state.wakeups.try_emplace(
      logical, state.publicationCause
                   ? state.publicationCause
                   : talos_rt_saif_capture_cause_unlocked(context));
}
void talos_rt_saif_complete_unlocked(talos_rt_context *context,
                                     uint64_t logical) {
  auto &state = *context->saif;
  state.wakeups.erase(logical);
  state.resumptions.erase(logical);
}
void talos_rt_saif_wake_actor_unlocked(talos_rt_context *context,
                                       uint32_t slot) {
  if (slot >= context->nativeScheduleActorIndices.size())
    return;
  size_t index = context->nativeScheduleActorIndices[slot];
  if (index < context->scheduledProcesses.size())
    talos_rt_saif_wake_unlocked(context,
                                TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG |
                                    context->scheduledProcesses[index].token);
}
void talos_rt_saif_direct_enter_unlocked(talos_rt_context *context,
                                         uint64_t logical) {
  directFrames.push_back(active);
  enter(context, logical);
}
void talos_rt_saif_direct_leave_unlocked(talos_rt_context *) {
  if (!directFrames.empty()) {
    auto *context = active.context;
    if (context)
      context->saif->resumptions.erase(active.logical);
    active = std::move(directFrames.back());
    directFrames.pop_back();
    if (context)
      context->saif->activeLogical =
          active.context == context ? active.logical : 0;
  }
}
SAIFExecutionScope::SAIFExecutionScope(
    talos_rt_context *context, uint64_t logical,
    const talos_rt_fragment_action_v1 *result)
    : result(result) {
  if (!context || !context->saif)
    return;
  ContextMutexLock lock(context);
  enabled = true;
  previousContext = active.context;
  previousCause = active.cause;
  previousLogical = active.logical;
  enter(context, logical);
}
SAIFExecutionScope::SAIFExecutionScope(talos_rt_context *context,
                                       std::shared_ptr<const SAIFCause> cause) {
  if (!context || !context->saif)
    return;
  ContextMutexLock lock(context);
  enabled = true;
  previousContext = active.context;
  previousCause = active.cause;
  previousLogical = active.logical;
  active = {context, cause ? std::move(cause) : fresh(context), 0};
  context->saif->activeLogical = 0;
  context->saif->publicationCause = active.cause;
}
SAIFExecutionScope::~SAIFExecutionScope() {
  if (enabled) {
    auto *context = active.context;
    ContextMutexLock lock(context);
    if (result && active.logical) {
      bool terminate = result->kind == TALOS_RT_FRAGMENT_TERMINATE;
      if (terminate) {
        uint64_t token = active.logical & ~TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG;
        if (active.logical & TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG) {
          auto process = context->scheduledProcessIndices.find(token);
          if (process != context->scheduledProcessIndices.end()) {
            const auto &owner = context->scheduledProcesses[process->second];
            terminate = owner.callers.empty() &&
                        (!owner.instance || owner.instance->lifecycle ==
                                                TALOS_RT_PROCESS_TERMINATED);
          }
        } else {
          auto task = context->scheduledDesignTaskIndices.find(token);
          if (task != context->scheduledDesignTaskIndices.end())
            terminate = context->scheduledDesignTasks[task->second].terminated;
        }
      }
      bool newWait = result->kind == TALOS_RT_FRAGMENT_SUSPEND &&
                     result->suspend_kind != TALOS_RT_SUSPEND_DELAY;
      if (terminate || newWait)
        context->saif->resumptions.erase(active.logical);
      if (terminate)
        context->saif->wakeups.erase(active.logical);
    }
    active = {previousContext, std::move(previousCause), previousLogical};
    context->saif->activeLogical =
        active.context == context ? active.logical : 0;
    context->saif->publicationCause =
        active.context == context ? active.cause : nullptr;
  }
}

extern "C" void talos_rt_v1_saif_driver(talos_rt_context *context,
                                        uint64_t handle, uint64_t width) {
  if (!context || !context->saif || !width)
    return;
  TALOS_RT_TRY {
    ContextMutexLock lock(context);
    uint32_t id;
    int64_t offset;
    if (!decodeNativeStatic(handle, id, offset) || offset < 0)
      return;
    const auto *native = findNativeStaticState(context, id);
    if (!native || uint64_t(offset) >= native->bitWidth ||
        width > native->bitWidth - offset)
      return;
    talos::designbytecode::Image image;
    talos_rt_design_bytecode_entry_v1 entry{context->execution, 0, 0};
    if (!talos::designbytecode::loadValidatedImage(entry, context, image, true))
      return;
    auto *cache = talos::designbytecode::getNetAliasCache(image, context);
    if (!cache)
      return;
    auto &state = *context->saif;
    if (!state.indexedDrivers) {
      for (const auto &driver : cache->drivers)
        state.driverRanges.push_back({driver.valueOffset,
                                      driver.valueOffset + driver.width,
                                      driver.targetOffset});
      std::sort(state.driverRanges.begin(), state.driverRanges.end(),
                [](auto a, auto b) { return a.begin < b.begin; });
      state.indexedDrivers = true;
    }
    uint64_t begin = native->bitOffset + offset, end = begin + width;
    auto it = std::lower_bound(
        state.driverRanges.begin(), state.driverRanges.end(), begin,
        [](const auto &range, uint64_t bit) { return range.end <= bit; });
    std::unordered_set<uint64_t> roots;
    for (; it != state.driverRanges.end() && it->begin < end; ++it)
      for (uint64_t bit = std::max(begin, it->begin);
           bit < std::min(end, it->end); ++bit) {
        auto found = cache->rootByBit.find(it->target + bit - it->begin);
        if (found != cache->rootByBit.end())
          roots.insert(found->second);
      }
    for (uint64_t root : roots)
      talos::designbytecode::collectSAIFContention(context, *cache, root);
  }
  TALOS_RT_CATCH(const std::bad_alloc &) {
    context->schedulerStatus = TALOS_RT_OUT_OF_MEMORY;
  }
  TALOS_RT_CATCH_ALL { context->schedulerStatus = TALOS_RT_INVALID_ARGUMENT; }
}

void talos_rt_saif_event_issued_unlocked(talos_rt_context *context,
                                         ScheduledNBA &event) {
  if (!event.saifCause)
    event.saifCause = talos_rt_saif_capture_cause_unlocked(context);
  event.saifInputTime = context->schedulerTime;
}

namespace {
std::optional<uint64_t> absoluteBit(talos_rt_context *context,
                                    uint64_t handle) {
  talos_rt_stable_handle_v1 decoded{};
  if (!talos_rt_stable_handle_decode(handle, &decoded) || decoded.offset < 0)
    return {};
  if (decoded.kind == TALOS_RT_STABLE_HANDLE_GLOBAL)
    return uint64_t(decoded.offset);
  if (decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC)
    return {};
  auto *native = findNativeStaticState(context, decoded.id);
  if (!native || uint64_t(decoded.offset) >= native->bitWidth)
    return {};
  return native->bitOffset + decoded.offset;
}
void observationsAt(talos_rt_context *context, uint64_t absolute,
                    std::unordered_set<size_t> &points) {
  uint64_t handle =
      talos_rt_canonical_state_handle_unlocked(context, absolute, 1);
  uint32_t id;
  int64_t offset;
  if (!decodeNativeStatic(handle, id, offset) || offset < 0)
    return;
  auto found = context->saif->watches.find(id);
  if (found == context->saif->watches.end())
    return;
  auto it = std::lower_bound(
      found->second.begin(), found->second.end(), uint64_t(offset),
      [](const Watch &watch, uint64_t bit) { return watch.bit < bit; });
  for (; it != found->second.end() && it->bit == uint64_t(offset); ++it)
    points.insert(it->observation);
}
void recordRejectedAt(talos_rt_context *context, uint64_t absolute, bool from,
                      bool to, const ScheduledNBA &leading) {
  uint64_t delay = leading.dueTime - leading.saifInputTime;
  long double weight =
      static_cast<long double>(context->schedulerTime - leading.saifInputTime) /
      delay;
  std::unordered_set<size_t> points;
  observationsAt(context, absolute, points);
  auto *cache = talos::designbytecode::getNetAliasCache(
      context->designBytecodeImage, context);
  if (cache)
    for (const auto &driver : cache->drivers) {
      if (absolute < driver.valueOffset ||
          absolute - driver.valueOffset >= driver.width)
        continue;
      auto root = cache->rootByBit.find(driver.targetOffset + absolute -
                                        driver.valueOffset);
      if (root != cache->rootByBit.end()) {
        auto members = cache->members.find(root->second);
        if (members != cache->members.end())
          for (uint64_t member : members->second)
            observationsAt(context, member, points);
      }
    }
  for (size_t point : points) {
    auto &counts = context->saif->observations[point].extra;
    if (counts.ig > UINT64_MAX - 2) {
      context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
      return;
    }
    counts.ig += 2;
    counts.weightedIG += 2 * weight;
    recordCellEdge(*context->saif, point, from, to, 2, leading.saifCause,
                   weight);
    recordCellEdge(*context->saif, point, to, from, 2,
                   talos_rt_saif_current_cause_unlocked(context), weight);
  }
}
} // namespace
void talos_rt_saif_reject_pulse_unlocked(talos_rt_context *context,
                                         const ScheduledNBA &leading,
                                         uint64_t destination, uint64_t width,
                                         const uint8_t *value,
                                         const uint8_t *unknown) {
  if (!leading.saifCause || leading.cancelled ||
      leading.inertialDriverInitialProjection ||
      leading.inertialNetInitialProjection || !value ||
      leading.dueTime <= context->schedulerTime ||
      leading.saifInputTime > context->schedulerTime ||
      leading.dueTime <= leading.saifInputTime)
    return;
  auto first = absoluteBit(context, leading.bitOffset),
       target = absoluteBit(context, destination);
  if (!first || !target || width > UINT64_MAX - *target)
    return;
  auto read = [&](bool u, uint64_t bit) {
    const auto &plane = u ? context->stateUnknown : context->stateValue;
    return bit / 64 < plane.size() &&
           ((plane[bit / 64] >> (bit % 64)) & 1) != 0;
  };
  for (uint64_t bit = 0; bit < leading.bitWidth; ++bit) {
    uint64_t absolute = *first + bit;
    if (absolute < *target || absolute - *target >= width)
      continue;
    bool from = read(false, absolute), fromUnknown = read(true, absolute);
    const uint8_t *leadingValue =
        leading.inlinePacked
            ? reinterpret_cast<const uint8_t *>(&leading.inlineValue)
            : leading.value.data();
    const uint8_t *leadingUnknown =
        leading.inlinePacked
            ? reinterpret_cast<const uint8_t *>(&leading.inlineUnknown)
            : leading.unknown.data();
    bool to = byteBit(leadingValue, bit);
    bool toUnknown = (leading.inlinePacked || !leading.unknown.empty()) &&
                     byteBit(leadingUnknown, bit);
    uint64_t relative = absolute - *target;
    if (fromUnknown || toUnknown || from == to || byteBit(unknown, relative) ||
        byteBit(value, relative) != from)
      continue;
    recordRejectedAt(context, absolute, from, to, leading);
  }
}

void talos_rt_saif_reject_pair_unlocked(
    talos_rt_context *context, const ScheduledNBA &low,
    const ScheduledNBA &high, uint64_t lowDestination, uint64_t highDestination,
    uint64_t width, const uint8_t *lowValue, const uint8_t *lowUnknown,
    const uint8_t *highValue, const uint8_t *highUnknown) {
  if (!low.saifCause || low.cancelled || high.cancelled ||
      low.dueTime <= context->schedulerTime || low.dueTime != high.dueTime ||
      low.saifInputTime > context->schedulerTime ||
      low.dueTime <= low.saifInputTime || low.inertialDriverInitialProjection ||
      high.inertialDriverInitialProjection || !low.inlinePacked ||
      !high.inlinePacked || low.bitWidth != 1 || high.bitWidth != 1 ||
      !lowValue || !highValue)
    return;
  auto lo = absoluteBit(context, low.bitOffset),
       hi = absoluteBit(context, high.bitOffset);
  auto targetLo = absoluteBit(context, lowDestination),
       targetHi = absoluteBit(context, highDestination);
  if (!lo || !hi || !targetLo || !targetHi || *lo < *targetLo ||
      *hi < *targetHi || *lo - *targetLo >= width ||
      *hi - *targetHi != *lo - *targetLo)
    return;
  auto symbol = [](bool lv, bool lu, bool hv, bool hu) -> unsigned {
    if (!lu && !lv && hu && hv)
      return 0;
    if (lu && lv && !hu && hv)
      return 1;
    return 2;
  };
  auto bit = [&](const CanonicalPlane &plane, uint64_t index) {
    return ((plane[index / 64] >> (index % 64)) & 1) != 0;
  };
  auto from =
      symbol(bit(context->stateValue, *lo), bit(context->stateUnknown, *lo),
             bit(context->stateValue, *hi), bit(context->stateUnknown, *hi));
  auto to = symbol(low.inlineValue, low.inlineUnknown, high.inlineValue,
                   high.inlineUnknown);
  uint64_t selected = *lo - *targetLo;
  auto trailing =
      symbol(byteBit(lowValue, selected), byteBit(lowUnknown, selected),
             byteBit(highValue, selected), byteBit(highUnknown, selected));
  if (from < 2 && to < 2 && from != to && trailing == from)
    recordRejectedAt(context, *lo, from, to, low);
}
