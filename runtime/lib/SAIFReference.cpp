//===- SAIFReference.cpp - Settled zero-delay combinational reference -----===//

#include "DesignBytecodeNets.h"
#include "ProcessContext.h"
#include "ProcessPacking.h"
#include "ProcessShared.h"
#include "SAIFInternal.h"

using namespace talos::saifruntime;
using namespace talos::designbytecode;

namespace {
talos_rt_context *referenceContext(talos_rt_context *context) {
  auto &state = *context->saif;
  if (state.referenceContext)
    return state.referenceContext.get();
  if (!context->execution || !context->designBytecodeImageValidated)
    return nullptr;
  talos_rt_context *reference = nullptr;
  auto status =
      talos_rt_v1_context_create_for_design(context->execution, &reference);
  if (status != TALOS_RT_OK) {
    context->schedulerStatus = status;
    return nullptr;
  }
  state.referenceContext = {reference, talos_rt_v1_context_destroy};
  reference->saifReferenceModel = true;
  reference->coverage.reset();
  reference->nativeStaticStates = context->nativeStaticStates;
  auto observations = std::make_shared<SAIFState>();
  observations->sealed = true;
  observations->observations = state.observations;
  observations->watches = state.watches;
  observations->referenceDirty.resize(state.observations.size(), false);
  for (auto &point : observations->observations) {
    point.referenceLast = point.current;
    point.cells.clear();
  }
  reference->saif = std::move(observations);
  return reference;
}

bool eligible(talos_rt_context *context, uint32_t function) {
  const auto &image = context->designBytecodeImage;
  return image.data && function < image.functionCount &&
         (functionAt(image, function).flags &
          TALOS_RT_DESIGN_FUNCTION_SAIF_REFERENCE);
}
} // namespace

void talos_rt_saif_clone_process_unlocked(
    talos_rt_context *context, uint64_t logical,
    const talos_rt_process_spawn_plan_v1 &plan, const void *captures) {
  if (!context->saif || context->saifReferenceModel ||
      !plan.descriptor->design_bytecode ||
      !eligible(context, plan.descriptor->design_bytecode->function))
    return;
  auto *reference = referenceContext(context);
  if (!reference)
    return;
  talos_rt_process_instance_v1 *instance = nullptr;
  auto status = talos_rt_v1_process_instance_create_for_context(
      reference, plan.descriptor, &instance);
  if (status != TALOS_RT_OK) {
    context->schedulerStatus = status;
    return;
  }
  if (plan.capture_size)
    std::memcpy(instance->frame, captures, plan.capture_size);
  instance->tier = TALOS_RT_TIER_BYTECODE;
  status = talos_rt_v1_scheduler_add_planned(
      reference, instance, plan.schedule_flags, plan.initial_rank,
      plan.continuations, plan.ranks, plan.continuation_count);
  if (status != TALOS_RT_OK) {
    talos_rt_v1_process_instance_destroy(instance);
    context->schedulerStatus = status;
    return;
  }
  context->saif->referenceProcesses.insert(logical);
  uint64_t referenceLogical =
      talos_rt_v1_scheduler_process_token(reference, instance) |
      TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG;
  reference->saif->referenceProcesses.insert(referenceLogical);
}

void talos_rt_saif_clone_task_unlocked(talos_rt_context *context,
                                       const ScheduledDesignTask &source) {
  if (!context->saif || context->saifReferenceModel ||
      !eligible(context, source.function))
    return;
  auto *reference = referenceContext(context);
  if (!reference)
    return;
  ScheduledDesignTask task;
  task.id = reference->nextDesignTaskID++;
  task.function = source.function;
  task.frame = source.frame;
  task.scratchOffset = source.scratchOffset;
  task.scratchSize = source.scratchSize;
  task.homeRegion = source.homeRegion;
  task.queuedRegion = task.homeRegion;
  task.scheduleRank = source.scheduleRank;
  task.insertionSequence = reference->nextProcessInsertionSequence++;
  task.observedEpoch = reference->schedulerEpoch;
  reference->scheduledDesignTaskIndices[task.id] =
      reference->scheduledDesignTasks.size();
  reference->designPollCandidates.insert(task.id);
  reference->scheduledDesignTasks.push_back(std::move(task));
  reference->saif->referenceProcesses.insert(
      reference->scheduledDesignTasks.back().id);
  context->saif->referenceProcesses.insert(source.id);
}

namespace talos::saifruntime {
void settleReference(talos_rt_context *context) {
  auto &state = *context->saif;
  auto *reference = state.referenceContext.get();
  if (!reference || context->saifReferenceModel)
    return;
  if (!state.referenceStarted) {
    if (!importNativeRootInitializerPlanesUnlocked(context)) {
      context->schedulerStatus = TALOS_RT_INVALID_DESIGN;
      return;
    }
    reference->stateValue = context->stateValue;
    reference->stateUnknown = context->stateUnknown;
    // A delayed publication may have established canonical state before the
    // first reference invocation. Seed shadows from exactly the same image;
    // otherwise a quiet initial driver never publishes its known value and
    // a subsequent reference 0->1 would appear to start at Z.
    for (const auto &[id, watches] : state.watches) {
      const auto *native = findNativeStaticState(context, id);
      if (!native)
        continue;
      for (auto watch : watches) {
        uint64_t bit = native->bitOffset + watch.bit;
        auto &point = reference->saif->observations[watch.observation];
        point.current =
            ((reference->stateValue[bit / 64] >> (bit % 64)) & 1) |
            (((reference->stateUnknown[bit / 64] >> (bit % 64)) & 1) << 1);
        point.referenceLast = point.current;
        // Time-zero initialization precedes the reference's first settle.
        // Use the same committed starting history in both models.
        for (unsigned polarity = 0; polarity < 2; ++polarity)
          state.observations[watch.observation].referenceEdges[polarity] =
              state.observations[watch.observation].physicalEdges[polarity];
      }
    }
    state.referenceStarted = true;
  }
  reference->schedulerTime = state.referenceTime;
  reference->saifReferenceBudget = 1000000;
  auto status = talos_rt_v1_scheduler_run(reference);
  if (status != TALOS_RT_OK) {
    context->schedulerStatus = status;
    return;
  }
  for (size_t i : reference->saif->referenceTouched) {
    auto &point = reference->saif->observations[i];
    if (point.current < 2 && point.referenceLast < 2 &&
        point.current != point.referenceLast) {
      auto &credit = state.observations[i].referenceEdges[point.current];
      if (credit == UINT64_MAX) {
        context->schedulerStatus = TALOS_RT_OUT_OF_RESOURCES;
        return;
      }
      ++credit;
    }
    point.referenceLast = point.current;
    reference->saif->referenceDirty[i] = false;
  }
  reference->saif->referenceTouched.clear();
}

void advanceReference(talos_rt_context *context) {
  if (context->saifReferenceModel)
    return;
  auto &state = *context->saif;
  if (context->schedulerTime != state.referenceTime) {
    settleReference(context);
    state.referenceTime = context->schedulerTime;
  }
}

void referenceTransition(talos_rt_context *context, uint64_t handle,
                         uint64_t width, const uint8_t *changed,
                         const uint8_t *value, const uint8_t *unknown) {
  if (context->saifReferenceModel)
    return;
  advanceReference(context);
  auto &state = *context->saif;
  // Combinational physical outputs are intentionally absent from the input
  // stream: replay computes them from boundary state with delays removed.
  if (state.referenceProcesses.count(state.activeLogical))
    return;
  auto cause = talos_rt_saif_current_cause_unlocked(context);
  if (cause && cause->referenceOutput)
    return;
  auto *reference = state.referenceContext.get();
  if (!reference || !state.referenceStarted)
    return;
  uint32_t id;
  int64_t offset;
  if (!decodeNativeStatic(handle, id, offset) || offset < 0)
    return;
  const auto *native = findNativeStaticState(context, id);
  if (!native || uint64_t(offset) >= native->bitWidth ||
      width > native->bitWidth - offset)
    return;
  size_t bytes = (width + 7) / 8;
  std::vector<uint8_t> v(bytes), u(bytes), c(bytes), pos(bytes), neg(bytes);
  bool any = false;
  for (uint64_t bit = 0; bit < width; ++bit) {
    uint64_t absolute = native->bitOffset + offset + bit;
    uint64_t mask = uint64_t{1} << (absolute % 64);
    bool oldV = (reference->stateValue[absolute / 64] & mask) != 0;
    bool oldU = (reference->stateUnknown[absolute / 64] & mask) != 0;
    bool newV = byteBit(changed, bit)
                    ? value ? byteBit(value, bit)
                            : (context->stateValue[absolute / 64] & mask) != 0
                    : oldV;
    bool newU = byteBit(changed, bit)
                    ? value ? byteBit(unknown, bit)
                            : (context->stateUnknown[absolute / 64] & mask) != 0
                    : oldU;
    uint8_t packed = uint8_t(1) << (bit % 8);
    if (newV)
      v[bit / 8] |= packed;
    if (newU)
      u[bit / 8] |= packed;
    if (oldV == newV && oldU == newU)
      continue;
    any = true;
    c[bit / 8] |= packed;
    uint32_t edges = transitionEdges(oldV, oldU, newV, newU);
    if (edges & TALOS_RT_SIGNAL_POSEDGE)
      pos[bit / 8] |= packed;
    if (edges & TALOS_RT_SIGNAL_NEGEDGE)
      neg[bit / 8] |= packed;
    reference->stateValue[absolute / 64] =
        (reference->stateValue[absolute / 64] & ~mask) | (newV ? mask : 0);
    reference->stateUnknown[absolute / 64] =
        (reference->stateUnknown[absolute / 64] & ~mask) | (newU ? mask : 0);
  }
  if (!any)
    return;
  reference->schedulerTime = context->schedulerTime;
  SAIFExecutionScope activity(reference, cause);
  if (!talos_rt_publish_native_signal_transition_unlocked(
          reference, handle, width, c.data(), pos.data(), neg.data(), nullptr,
          nullptr, v.data(), u.data())) {
    context->schedulerStatus = reference->schedulerStatus;
    return;
  }
  bool resolved = false;
  if (!resolveDrivenNets(reference->designBytecodeImage, reference,
                         native->bitOffset + offset,
                         native->bitOffset + offset + width, resolved))
    context->schedulerStatus = reference->schedulerStatus;
}
} // namespace talos::saifruntime
