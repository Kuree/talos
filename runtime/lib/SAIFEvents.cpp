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

void talos_rt_saif_event_issued_unlocked(talos_rt_context *context,
                                         ScheduledNBA &event) {
  if (!event.saifCause)
    event.saifCause = talos_rt_saif_capture_cause_unlocked(context);
}
