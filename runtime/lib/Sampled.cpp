//===- Sampled.cpp - Preponed sampled-value history ---------------------===//

#include "ProcessContext.h"
#include "RuntimeInternal.h"

#include "talos/Runtime/StableHandle.h"

#include <cstring>
#include <limits>

namespace {

bool checkedBytes(uint64_t bits, size_t &bytes) {
  if (bits == 0 || bits > UINT64_MAX - 7)
    return false;
  uint64_t count = (bits + 7) / 8;
  if (count > std::numeric_limits<size_t>::max())
    return false;
  bytes = static_cast<size_t>(count);
  return true;
}

const talos_rt_execution_extension_v1 *
executionExtension(const talos_rt_execution_descriptor_v1 &execution) {
  return reinterpret_cast<const talos_rt_execution_extension_v1 *>(
      reinterpret_cast<const uint8_t *>(&execution) + execution.reserved);
}

void copyPackedRange(uint8_t *destination, const uint8_t *source,
                     uint64_t sourceBytes, uint64_t sourceBit,
                     uint64_t bitWidth) {
  size_t bytes = static_cast<size_t>((bitWidth + 7) / 8);
  unsigned shift = static_cast<unsigned>(sourceBit % 8);
  uint64_t sourceByte = sourceBit / 8;
  if (shift == 0) {
    if (bytes == 1)
      destination[0] = source[sourceByte];
    else
      std::memcpy(destination, source + sourceByte, bytes);
  } else {
    for (size_t index = 0; index != bytes; ++index) {
      uint16_t value = source[sourceByte + index];
      if (sourceByte + index + 1 < sourceBytes)
        value |= static_cast<uint16_t>(source[sourceByte + index + 1]) << 8;
      destination[index] = static_cast<uint8_t>(value >> shift);
    }
  }
  if (bitWidth % 8 != 0)
    destination[bytes - 1] &= static_cast<uint8_t>((1u << (bitWidth % 8)) - 1);
}

bool resolveCanonicalRange(const talos_rt_context *context, uint64_t handle,
                           uint64_t width, uint64_t &start) {
  talos_rt_stable_handle_v1 decoded{};
  if (!talos_rt_stable_handle_decode(handle, &decoded) || decoded.offset < 0)
    return false;
  uint64_t offset = static_cast<uint64_t>(decoded.offset);
  if (decoded.kind == TALOS_RT_STABLE_HANDLE_GLOBAL) {
    start = offset;
  } else if (decoded.kind == TALOS_RT_STABLE_HANDLE_STATIC) {
    const NativeStaticState *state = nullptr;
    if (decoded.id < context->nativeScheduleStaticStateIndex.size() &&
        context->nativeScheduleStaticStateIndex[decoded.id].bitWidth != 0)
      state = &context->nativeScheduleStaticStateIndex[decoded.id];
    else if (auto found = context->nativeStaticStates.find(decoded.id);
             found != context->nativeStaticStates.end())
      state = &found->second;
    if (!state || offset > state->bitWidth || width > state->bitWidth - offset)
      return false;
    start = state->bitOffset + offset;
  } else {
    return false;
  }
  uint64_t total = context->execution ? context->execution->state_bit_count : 0;
  return start <= total && width <= total - start;
}

bool resolveSnapshotRange(const talos_rt_context *context,
                          uint64_t canonicalStart, uint64_t width,
                          uint64_t &snapshotStart) {
  const talos_rt_execution_descriptor_v1 *execution = context->execution;
  const talos_rt_execution_extension_v1 *extension =
      execution ? executionExtension(*execution) : nullptr;
  uint64_t low = 0, high = extension ? extension->sampled_range_count : 0;
  while (low < high) {
    uint64_t middle = low + (high - low) / 2;
    if (extension->sampled_ranges[middle].source_bit_offset <= canonicalStart)
      low = middle + 1;
    else
      high = middle;
  }
  if (low == 0)
    return false;
  const talos_rt_sampled_range_v1 &range = extension->sampled_ranges[low - 1];
  uint64_t relative = canonicalStart - range.source_bit_offset;
  if (relative > range.bit_width || width > range.bit_width - relative)
    return false;
  snapshotStart = range.snapshot_byte_offset * 8 + relative;
  return true;
}

} // namespace

talos_rt_status
talos_rt_capture_preponed_unlocked(talos_rt_context *context,
                                   talos_rt_sampled_plane_copy copy) {
  if (!context)
    return TALOS_RT_INVALID_ARGUMENT;
  if (!context->execution ||
      (context->execution->flags & TALOS_RT_EXECUTION_PREPONED_SNAPSHOT) == 0)
    return TALOS_RT_OK;
  TALOS_RT_TRY {
    const talos_rt_execution_descriptor_v1 &execution = *context->execution;
    const talos_rt_execution_extension_v1 &extension =
        *executionExtension(execution);
    if (!context->sampledCapturePlan) {
      auto plan = std::make_unique<talos_rt_context::SampledCapturePlan>();
      for (uint64_t i = 0; i < extension.sampled_range_count; ++i) {
        auto range = extension.sampled_ranges[i];
        unsigned shift = range.source_bit_offset % 8;
        if (range.bit_width <= 8 - shift) {
          plan->bytes.push_back({range.source_bit_offset / 8,
                                 range.snapshot_byte_offset, uint8_t(shift),
                                 uint8_t((1u << range.bit_width) - 1)});
          continue;
        }
        // Adjacent whole bytes have the same layout in both planes. A
        // partial range keeps its own mask and public sampled bounds.
        if (!plan->ranges.empty() && shift == 0 && range.bit_width % 8 == 0) {
          auto &prev = plan->ranges.back();
          if (prev.source_bit_offset % 8 == 0 && prev.bit_width % 8 == 0 &&
              prev.source_bit_offset + prev.bit_width ==
                  range.source_bit_offset &&
              prev.snapshot_byte_offset + prev.bit_width / 8 ==
                  range.snapshot_byte_offset) {
            prev.bit_width += range.bit_width;
            continue;
          }
        }
        plan->ranges.push_back(range);
      }
      const auto &last =
          extension.sampled_ranges[extension.sampled_range_count - 1];
      uint64_t snapshotBytes =
          last.snapshot_byte_offset + (last.bit_width + 7) / 8;
      size_t words = static_cast<size_t>((snapshotBytes + 7) / 8);
      context->preponedValue.resize(words);
      if (!context->twoState())
        context->preponedUnknown.resize(words);
      context->preponedPlanes = {context->preponedValue.data(),
                                 context->preponedUnknown.data()};
      context->sampledCapturePlan = std::move(plan);
    }

    const uint8_t *value = nullptr;
    const uint8_t *unknown = nullptr;
    if (context->nativeSchedulePlan &&
        context->nativeSchedulePlan->state_bit_count ==
            execution.state_bit_count) {
      value = context->nativeSchedulePlan->state_value;
      unknown = context->nativeSchedulePlan->state_unknown;
    } else if (context->nativeStateBitCount == execution.state_bit_count) {
      value = context->nativeStateValue;
      unknown = context->nativeStateUnknown;
    }
    if (!value || (!unknown && !context->twoState())) {
      size_t stateWords =
          static_cast<size_t>((execution.state_bit_count + 63) / 64);
      if (context->stateValue.size() != stateWords ||
          context->stateUnknown.size() != stateWords)
        return TALOS_RT_INVALID_DESIGN;
      value = reinterpret_cast<const uint8_t *>(context->stateValue.data());
      unknown = reinterpret_cast<const uint8_t *>(context->stateUnknown.data());
    }
    uint8_t *sampledValue =
        reinterpret_cast<uint8_t *>(context->preponedValue.data());
    uint8_t *sampledUnknown =
        reinterpret_cast<uint8_t *>(context->preponedUnknown.data());
    if (copy) {
      copy(value, sampledValue);
      if (sampledUnknown)
        copy(unknown, sampledUnknown);
      return TALOS_RT_OK;
    }
    uint64_t stateBytes = (execution.state_bit_count + 7) / 8;
    for (const auto &copy : context->sampledCapturePlan->bytes) {
      sampledValue[copy.destination] =
          (value[copy.source] >> copy.shift) & copy.mask;
      if (sampledUnknown)
        sampledUnknown[copy.destination] =
            (unknown[copy.source] >> copy.shift) & copy.mask;
    }
    for (const auto &range : context->sampledCapturePlan->ranges) {
      copyPackedRange(sampledValue + range.snapshot_byte_offset, value,
                      stateBytes, range.source_bit_offset, range.bit_width);
      if (sampledUnknown)
        copyPackedRange(sampledUnknown + range.snapshot_byte_offset, unknown,
                        stateBytes, range.source_bit_offset, range.bit_width);
    }
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}

talos_rt_status
talos_rt_recapture_initialized_preponed_unlocked(talos_rt_context *context) {
  if (context->schedulerTime != 0 || context->preponedValue.empty())
    return TALOS_RT_OK;
  return talos_rt_capture_preponed_unlocked(context);
}

extern "C" const uint64_t *
talos_rt_v1_sampled_plane(const talos_rt_context *context, uint32_t unknown) {
  if (!context)
    return nullptr;
  return unknown ? context->preponedPlanes.unknown
                 : context->preponedPlanes.value;
}

extern "C" uint64_t talos_rt_v1_sampled_word(talos_rt_context *context,
                                             uint64_t word, uint32_t unknown) {
  if (!context)
    return 0;
  ContextMutexLock lock(context);
  if (word < context->preponedValue.size()) {
    if (!unknown)
      return context->preponedValue[word];
    if (word < context->preponedUnknown.size())
      return context->preponedUnknown[word];
    if (context->twoState())
      return 0;
  }
  talos_rt_v1_scheduler_fail(context, TALOS_RT_INVALID_HANDLE);
  return 0;
}

extern "C" talos_rt_status talos_rt_v1_sampled_read(talos_rt_context *context,
                                                    uint64_t stableID,
                                                    uint64_t bitWidth,
                                                    uint8_t *outValue,
                                                    uint8_t *outUnknown) {
  size_t bytes = 0;
  if (!context || !outValue || !outUnknown || !checkedBytes(bitWidth, bytes))
    return TALOS_RT_INVALID_ARGUMENT;
  // Fixed-array selection uses this sentinel for an unknown or out-of-range
  // index. Its read is X (zero after conversion to two-state), just as an
  // ordinary invalid array read; it is not a missing runtime object.
  if (stableID == UINT64_MAX) {
    std::memset(outValue, 0, bytes);
    std::memset(outUnknown, UINT8_MAX, bytes);
    if (bitWidth % 8)
      outUnknown[bytes - 1] &= static_cast<uint8_t>((1u << (bitWidth % 8)) - 1);
    return TALOS_RT_OK;
  }
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    uint64_t canonicalStart = 0, snapshotStart = 0;
    if (!resolveCanonicalRange(context, stableID, bitWidth, canonicalStart) ||
        !resolveSnapshotRange(context, canonicalStart, bitWidth,
                              snapshotStart) ||
        context->preponedValue.empty() ||
        (context->preponedUnknown.empty() && !context->twoState()))
      return TALOS_RT_INVALID_HANDLE;
    auto copy = [&](uint8_t *destination, const std::vector<uint64_t> &plane) {
      copyPackedRange(destination,
                      reinterpret_cast<const uint8_t *>(plane.data()),
                      plane.size() * sizeof(uint64_t), snapshotStart, bitWidth);
    };
    copy(outValue, context->preponedValue);
    if (context->preponedUnknown.empty())
      std::memset(outUnknown, 0, bytes);
    else
      copy(outUnknown, context->preponedUnknown);
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}

extern "C" talos_rt_status talos_rt_v1_sampled_history(
    talos_rt_context *context, uint64_t siteID, uint64_t bitWidth,
    uint64_t depth, uint32_t fourState, uint32_t gate,
    const uint8_t *currentValue, const uint8_t *currentUnknown,
    uint8_t *outValue, uint8_t *outUnknown) {
  size_t bytes = 0;
  if (!context || siteID == 0 || depth == 0 || fourState > 1 || gate > 1 ||
      !currentValue || (fourState && !currentUnknown) || !outValue ||
      !outUnknown || !checkedBytes(bitWidth, bytes) ||
      depth > std::numeric_limits<size_t>::max() / bytes)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    if (context->activeLogicalProcessToken == 0)
      return TALOS_RT_INVALID_LIFECYCLE;
    SampledHistoryState &history =
        context->sampledHistories[context->activeLogicalProcessToken][siteID];
    if (history.bitWidth == 0) {
      history.bitWidth = bitWidth;
      history.depth = depth;
      history.value.assign(static_cast<size_t>(depth) * bytes, 0);
      if (fourState)
        history.unknown.assign(static_cast<size_t>(depth) * bytes,
                               fourState ? UINT8_MAX : 0);
      if (bitWidth % 8 != 0 && fourState)
        for (uint64_t index = 0; index != depth; ++index)
          history.unknown[index * bytes + bytes - 1] &=
              static_cast<uint8_t>((1u << (bitWidth % 8)) - 1);
    } else if (history.bitWidth != bitWidth || history.depth != depth) {
      return TALOS_RT_LAYOUT_MISMATCH;
    }

    uint64_t selected = history.count < depth ? history.count : history.next;
    std::memcpy(outValue, history.value.data() + selected * bytes, bytes);
    if (fourState)
      std::memcpy(outUnknown, history.unknown.data() + selected * bytes, bytes);
    else
      std::memset(outUnknown, 0, bytes);
    if (gate) {
      std::memcpy(history.value.data() + history.next * bytes, currentValue,
                  bytes);
      if (fourState)
        std::memcpy(history.unknown.data() + history.next * bytes,
                    currentUnknown, bytes);
      history.next = (history.next + 1) % depth;
      if (history.count < depth)
        ++history.count;
    }
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}

extern "C" talos_rt_status talos_rt_v1_clocked_sample_update(
    talos_rt_context *context, uint64_t siteID, uint64_t bitWidth,
    uint64_t depth, uint32_t fourState, uint32_t gate,
    const uint8_t *currentValue, const uint8_t *currentUnknown) {
  size_t bytes = 0;
  if (!context || siteID == 0 || depth == UINT64_MAX || fourState > 1 ||
      gate > 1 || !currentValue || (fourState && !currentUnknown) ||
      !checkedBytes(bitWidth, bytes) ||
      depth + 1 > std::numeric_limits<size_t>::max() / bytes)
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    uint64_t capacity = depth + 1;
    SampledHistoryState &history = context->clockedSampleHistories[siteID];
    if (history.bitWidth == 0) {
      history.bitWidth = bitWidth;
      history.depth = capacity;
      history.value.assign(static_cast<size_t>(capacity) * bytes, 0);
      if (fourState)
        history.unknown.assign(static_cast<size_t>(capacity) * bytes,
                               fourState ? UINT8_MAX : 0);
      if (bitWidth % 8 != 0 && fourState)
        for (uint64_t index = 0; index != capacity; ++index)
          history.unknown[index * bytes + bytes - 1] &=
              static_cast<uint8_t>((1u << (bitWidth % 8)) - 1);
    } else if (history.bitWidth != bitWidth || history.depth != capacity) {
      return TALOS_RT_LAYOUT_MISMATCH;
    }
    if (!gate)
      return TALOS_RT_OK;
    std::memcpy(history.value.data() + history.next * bytes, currentValue,
                bytes);
    if (fourState)
      std::memcpy(history.unknown.data() + history.next * bytes, currentUnknown,
                  bytes);
    history.next = (history.next + 1) % capacity;
    if (history.count < capacity)
      ++history.count;
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}

extern "C" talos_rt_status
talos_rt_v1_clocked_sample_read(talos_rt_context *context, uint64_t siteID,
                                uint64_t bitWidth, uint64_t depth, uint64_t age,
                                uint32_t fourState, uint8_t *outValue,
                                uint8_t *outUnknown) {
  size_t bytes = 0;
  if (!context || siteID == 0 || depth == UINT64_MAX || age > depth ||
      fourState > 1 || !outValue || !outUnknown ||
      !checkedBytes(bitWidth, bytes))
    return TALOS_RT_INVALID_ARGUMENT;
  ContextTransaction transaction(context);
  TALOS_RT_TRY {
    std::lock_guard<TalosContextMutex> lock(context->mutex);
    std::memset(outValue, 0, bytes);
    std::memset(outUnknown, fourState ? UINT8_MAX : 0, bytes);
    if (bitWidth % 8 != 0 && fourState)
      outUnknown[bytes - 1] &= static_cast<uint8_t>((1u << (bitWidth % 8)) - 1);
    auto found = context->clockedSampleHistories.find(siteID);
    if (found == context->clockedSampleHistories.end())
      return TALOS_RT_OK;
    const SampledHistoryState &history = found->second;
    uint64_t capacity = depth + 1;
    if (history.bitWidth != bitWidth || history.depth != capacity)
      return TALOS_RT_LAYOUT_MISMATCH;
    if (age >= history.count)
      return TALOS_RT_OK;
    uint64_t index = (history.next + capacity - 1 - age) % capacity;
    std::memcpy(outValue, history.value.data() + index * bytes, bytes);
    // A sampler whose operand folded to a two-state constant keeps no unknown
    // plane, and its samples are fully known to a four-state reader.
    if (fourState) {
      if (history.unknown.empty())
        std::memset(outUnknown, 0, bytes);
      else
        std::memcpy(outUnknown, history.unknown.data() + index * bytes, bytes);
    }
    return TALOS_RT_OK;
  }
  TALOS_RT_CATCH_ALL { return TALOS_RT_INVALID_DESIGN; }
}
