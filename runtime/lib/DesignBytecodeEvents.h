//===- DesignBytecodeEvents.h - Exact-event decoding -----------*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_DESIGNBYTECODEEVENTS_H
#define TALOS_RUNTIME_LIB_DESIGNBYTECODEEVENTS_H

#include "DesignBytecodeExecution.h"
#include "ProcessValidation.h"
#include "RuntimeInternal.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <new>
#include <optional>
#include <stdexcept>
#include <vector>

namespace talos::designbytecode {

inline std::optional<uint64_t> readScalar(const Image &image,
                                          const Frame &frame, uint32_t reg) {
  if (!validRegister(frame.function, reg))
    return std::nullopt;
  Layout layout = layoutAt(image, frame.function, reg);
  if ((layout.kind != TALOS_RT_DBREG_BITS &&
       layout.kind != TALOS_RT_DBREG_LOGIC) ||
      layout.width > 64)
    return std::nullopt;
  uint64_t value = 0;
  std::memcpy(&value, frame.data + layout.offset,
              static_cast<size_t>(std::min<uint64_t>(layout.size, 8)));
  if (layout.kind == TALOS_RT_DBREG_LOGIC) {
    uint64_t unknown = 0;
    std::memcpy(&unknown, frame.data + layout.offset + 8, sizeof(unknown));
    if (unknown != 0)
      return std::nullopt;
  }
  return value & finalMask(layout.width);
}
inline bool readObserverCapture(const Image &image, const Frame &frame,
                                uint32_t reg,
                                const talos_rt_observer_capture_abi_v1 &abi,
                                talos_rt_computed_capture_v1 &capture) {
  if (!validRegister(frame.function, reg))
    return false;
  Layout layout = layoutAt(image, frame.function, reg);
  capture = {};
  if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_ARGUMENT_REF) {
    if (layout.kind != TALOS_RT_DBREG_ARGUMENT_REF || layout.size != 24)
      return false;
    std::memcpy(&capture, frame.data + layout.offset, 24);
    return true;
  }
  if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_MANAGED) {
    if (layout.kind != TALOS_RT_DBREG_MANAGED || layout.size != 8)
      return false;
    std::memcpy(&capture.stable_id, frame.data + layout.offset, 8);
    return true;
  }
  if (abi.kind == TALOS_RT_OBSERVER_CAPTURE_COVERGROUP) {
    std::optional<uint64_t> value = readScalar(image, frame, reg);
    if (!value || layout.kind != TALOS_RT_DBREG_BITS || layout.width != 64)
      return false;
    capture.stable_id = *value;
    return true;
  }
  if (layout.kind != TALOS_RT_DBREG_HANDLE || layout.size != 32 ||
      (abi.kind != TALOS_RT_OBSERVER_CAPTURE_STORAGE &&
       abi.kind != TALOS_RT_OBSERVER_CAPTURE_NET &&
       abi.kind != TALOS_RT_OBSERVER_CAPTURE_EVENT &&
       abi.kind != TALOS_RT_OBSERVER_CAPTURE_DRIVER))
    return false;
  return encodeCanonicalHandle(frame.data + layout.offset, capture.stable_id);
}

// This is the existing exact-event decoder, specialized so snapshot-only
// references stay in the optional feature object. Specialization keeps the
// ordinary dispatcher free of that link without a new runtime entry point.
template <bool Snapshot>
inline talos_rt_status
decodeExactEventRegistration(const Image &image, Frame &frame,
                             talos_rt_context *context, IntrinsicSite site) {
  constexpr bool snapshot = Snapshot;
  auto inputRegister = [&](uint32_t index) {
    return operandAt(image, site.firstOperand + index).second;
  };
  auto scalar = [&](uint32_t index) {
    return readScalar(image, frame, inputRegister(index));
  };
  if (site.inputCount < 5)
    return TALOS_RT_INVALID_BYTECODE;
  auto clauseCountValue = scalar(0), conditionCountValue = scalar(1),
       strobeValue = scalar(2), observerCodeUnit = scalar(3),
       captureCountValue = scalar(4);
  if (!clauseCountValue || !conditionCountValue || !strobeValue ||
      !observerCodeUnit || !captureCountValue || *clauseCountValue == 0 ||
      *clauseCountValue > 64 || *conditionCountValue > *clauseCountValue ||
      (snapshot ? (*strobeValue == 0 || *strobeValue > UINT32_MAX ||
                   *strobeValue * 3 > site.inputCount)
                : *strobeValue > 1) ||
      *captureCountValue > UINT32_MAX)
    return TALOS_RT_INVALID_BYTECODE;
  uint32_t clauseCount = static_cast<uint32_t>(*clauseCountValue);
  uint32_t conditionCount = static_cast<uint32_t>(*conditionCountValue);
  uint32_t observerCount = clauseCount + conditionCount;
  uint32_t captureCount = static_cast<uint32_t>(*captureCountValue);
  struct ObserverMeta {
    uint64_t codeUnit = 0;
    uint32_t captures = 0;
    uint32_t dependencies = 0;
    uint32_t width = 0;
    bool fourState = false;
    const talos_rt_observer_descriptor_v1 *descriptor = nullptr;
  };
  std::vector<ObserverMeta> metadata;
  std::vector<uint32_t> edges;
  std::vector<int32_t> conditionIndices;
  std::vector<talos_rt_computed_capture_v1> samplerCaptures;
  std::vector<talos_rt_event_snapshot_target_v1> targets;
  static_assert(alignof(talos_rt_computed_wait_record_v1) <= alignof(uint64_t));
  std::vector<uint64_t> record;
  uint64_t recordSize = 0;
  uint32_t cursor = 5;
  auto hasInputs = [&](uint64_t count) {
    return cursor <= site.inputCount &&
           count <= uint64_t{site.inputCount - cursor};
  };
  TALOS_RT_TRY {
    metadata.resize(observerCount);
    uint64_t eventCaptureCount = 0;
    uint64_t dependencyCount = 0;
    uint64_t previousLimbs = 0;
    if (!hasInputs(uint64_t{observerCount} * 5))
      return TALOS_RT_INVALID_BYTECODE;
    for (uint32_t index = 0; index != observerCount; ++index) {
      auto codeUnit = scalar(cursor++), captures = scalar(cursor++),
           dependencies = scalar(cursor++), width = scalar(cursor++),
           fourState = scalar(cursor++);
      if (!codeUnit || !captures || !dependencies || !width || !fourState ||
          *codeUnit == 0 || *captures > UINT32_MAX ||
          *dependencies > UINT32_MAX || *width == 0 || *width > UINT32_MAX ||
          *fourState > 1)
        return TALOS_RT_INVALID_BYTECODE;
      const talos_rt_observer_descriptor_v1 *descriptor =
          talos::process::findObserverDescriptor(context->execution, *codeUnit);
      uint32_t expectedFlags =
          *fourState != 0 ? TALOS_RT_OBSERVER_FOUR_STATE : 0;
      if (!descriptor || descriptor->capture_count != *captures ||
          descriptor->result_width != *width ||
          descriptor->flags != expectedFlags ||
          (index >= clauseCount && *width != 1))
        return TALOS_RT_INVALID_BYTECODE;
      metadata[index] = {*codeUnit,
                         static_cast<uint32_t>(*captures),
                         static_cast<uint32_t>(*dependencies),
                         static_cast<uint32_t>(*width),
                         *fourState != 0,
                         descriptor};
      if (eventCaptureCount > UINT32_MAX - *captures ||
          dependencyCount > UINT32_MAX - *dependencies)
        return TALOS_RT_INVALID_BYTECODE;
      eventCaptureCount += *captures;
      dependencyCount += *dependencies;
      if (index < clauseCount) {
        uint64_t limbs = (*width + 63) / 64;
        if (previousLimbs > UINT32_MAX - limbs)
          return TALOS_RT_INVALID_BYTECODE;
        previousLimbs += limbs;
      }
    }
    if (!hasInputs(uint64_t{clauseCount} * 2))
      return TALOS_RT_INVALID_BYTECODE;
    edges.resize(clauseCount);
    conditionIndices.resize(clauseCount);
    for (uint32_t &edge : edges) {
      auto value = scalar(cursor++);
      if (!value || *value > TALOS_RT_WAIT_EDGE_BOTH)
        return TALOS_RT_INVALID_BYTECODE;
      edge = static_cast<uint32_t>(*value);
    }
    uint32_t nextCondition = 0;
    for (int32_t &condition : conditionIndices) {
      auto value = scalar(cursor++);
      if (!value || *value > UINT32_MAX)
        return TALOS_RT_INVALID_BYTECODE;
      uint32_t parsed = static_cast<uint32_t>(*value);
      if (parsed == UINT32_MAX) {
        condition = -1;
        continue;
      }
      if (parsed != nextCondition || parsed >= conditionCount)
        return TALOS_RT_INVALID_BYTECODE;
      condition = static_cast<int32_t>(parsed);
      ++nextCondition;
    }
    if (nextCondition != conditionCount)
      return TALOS_RT_INVALID_BYTECODE;

    uint64_t observersOffset = sizeof(talos_rt_computed_wait_record_v1);
    uint64_t capturesOffset =
        observersOffset +
        uint64_t{observerCount} * sizeof(talos_rt_computed_observer_v1);
    uint64_t dependenciesOffset =
        capturesOffset +
        eventCaptureCount * sizeof(talos_rt_computed_capture_v1);
    uint64_t clausesOffset =
        dependenciesOffset +
        dependencyCount * sizeof(talos_rt_computed_dependency_v1);
    uint64_t previousOffset =
        clausesOffset +
        uint64_t{clauseCount} * sizeof(talos_rt_computed_clause_v1);
    uint64_t totalSize = previousOffset + previousLimbs * 16;
    if (totalSize > UINT32_MAX || totalSize > SIZE_MAX)
      return TALOS_RT_INVALID_BYTECODE;
    recordSize = totalSize;
    uint64_t recordWords =
        totalSize / sizeof(uint64_t) + (totalSize % sizeof(uint64_t) != 0);
    record.assign(static_cast<size_t>(recordWords), 0);
    auto writeRecord = [&](uint64_t offset, const void *data, uint64_t size) {
      auto *bytes = reinterpret_cast<uint8_t *>(record.data());
      std::memcpy(bytes + offset, data, static_cast<size_t>(size));
    };
    talos_rt_computed_wait_record_v1 header{
        TALOS_RT_VERSION,
        TALOS_RT_SUSPEND_OBSERVER,
        TALOS_RT_COMPUTED_WAIT_INTERLEAVED,
        clauseCount,
        observerCount,
        static_cast<uint32_t>(eventCaptureCount),
        static_cast<uint32_t>(dependencyCount),
        static_cast<uint32_t>(previousLimbs),
        observersOffset,
        capturesOffset,
        dependenciesOffset,
        clausesOffset,
        previousOffset,
        0,
        totalSize,
        0};
    writeRecord(0, &header, sizeof(header));
    uint32_t captureCursor = 0;
    uint32_t dependencyCursor = 0;
    uint64_t previousCursor = 0;
    for (uint32_t index = 0; index != observerCount; ++index) {
      const ObserverMeta &meta = metadata[index];
      talos_rt_computed_observer_v1 observer{
          meta.codeUnit,
          captureCursor,
          meta.captures,
          dependencyCursor,
          meta.dependencies,
          index < clauseCount
              ? static_cast<uint32_t>(previousOffset + previousCursor * 16)
              : UINT32_MAX,
          0};
      writeRecord(observersOffset +
                      index * sizeof(talos_rt_computed_observer_v1),
                  &observer, sizeof(observer));
      captureCursor += meta.captures;
      dependencyCursor += meta.dependencies;
      if (index < clauseCount)
        previousCursor += (uint64_t{meta.width} + 63) / 64;
    }
    for (uint32_t index = 0; index != clauseCount; ++index) {
      talos_rt_computed_clause_v1 clause{
          index,
          conditionIndices[index] < 0
              ? TALOS_RT_OBSERVER_CONDITION_NONE
              : clauseCount + static_cast<uint32_t>(conditionIndices[index]),
          edges[index], 0};
      writeRecord(clausesOffset +
                      uint64_t{index} * sizeof(talos_rt_computed_clause_v1),
                  &clause, sizeof(clause));
    }
    uint32_t captureIndex = 0;
    for (const ObserverMeta &meta : metadata) {
      for (uint32_t local = 0; local != meta.captures;
           ++local, ++captureIndex) {
        if (cursor >= site.inputCount)
          return TALOS_RT_INVALID_BYTECODE;
        talos_rt_computed_capture_v1 capture{};
        if (!readObserverCapture(image, frame, inputRegister(cursor++),
                                 meta.descriptor->capture_abi[local], capture))
          return TALOS_RT_INVALID_BYTECODE;
        writeRecord(capturesOffset + uint64_t{captureIndex} *
                                         sizeof(talos_rt_computed_capture_v1),
                    &capture, sizeof(capture));
      }
    }
    if (!hasInputs(dependencyCount * 3))
      return TALOS_RT_INVALID_BYTECODE;
    for (uint32_t index = 0; index != dependencyCount; ++index) {
      auto stable = scalar(cursor++), kind = scalar(cursor++),
           width = scalar(cursor++);
      if (!stable || !kind || !width || *kind > UINT32_MAX ||
          *width > UINT32_MAX)
        return TALOS_RT_INVALID_BYTECODE;
      talos_rt_computed_dependency_v1 dependency{
          *stable, static_cast<uint32_t>(*kind), static_cast<uint32_t>(*width)};
      writeRecord(dependenciesOffset +
                      uint64_t{index} * sizeof(talos_rt_computed_dependency_v1),
                  &dependency, sizeof(dependency));
    }
    previousCursor = 0;
    for (uint32_t index = 0; index != clauseCount; ++index) {
      if (cursor >= site.inputCount)
        return TALOS_RT_INVALID_BYTECODE;
      Layout layout = layoutAt(image, frame.function, inputRegister(cursor++));
      if ((layout.kind != TALOS_RT_DBREG_BITS &&
           layout.kind != TALOS_RT_DBREG_LOGIC) ||
          layout.width != metadata[index].width ||
          (layout.kind == TALOS_RT_DBREG_LOGIC) != metadata[index].fourState)
        return TALOS_RT_INVALID_BYTECODE;
      Logic initial = readLogic(frame.data, layout);
      uint64_t limbs = (uint64_t{metadata[index].width} + 63) / 64;
      uint64_t offset = previousOffset + previousCursor * 16;
      writeRecord(offset, initial.value.data(), limbs * 8);
      if (metadata[index].fourState)
        writeRecord(offset + limbs * 8, initial.unknown.data(), limbs * 8);
      previousCursor += limbs;
    }
    const talos_rt_observer_descriptor_v1 *samplerDescriptor =
        talos::process::findObserverDescriptor(context->execution,
                                               *observerCodeUnit);
    if (!samplerDescriptor || samplerDescriptor->capture_count != captureCount)
      return TALOS_RT_INVALID_BYTECODE;
    samplerCaptures.resize(captureCount);
    for (uint32_t index = 0; index != captureCount; ++index) {
      if (cursor >= site.inputCount ||
          !readObserverCapture(image, frame, inputRegister(cursor++),
                               samplerDescriptor->capture_abi[index],
                               samplerCaptures[index]))
        return TALOS_RT_INVALID_BYTECODE;
    }
    if (snapshot) {
      uint64_t count = *strobeValue;
      if (cursor > site.inputCount || count * 3 != site.inputCount - cursor ||
          count > SIZE_MAX / sizeof(talos_rt_event_snapshot_target_v1))
        return TALOS_RT_INVALID_BYTECODE;
      targets.reserve(static_cast<size_t>(count));
      for (uint64_t index = 0; index < count; ++index) {
        auto handle = scalar(cursor++), width = scalar(cursor++),
             flags = scalar(cursor++);
        if (!handle || !width || !flags || !*width || *width > UINT32_MAX ||
            *flags > UINT32_MAX)
          return TALOS_RT_INVALID_BYTECODE;
        targets.push_back({*handle, static_cast<uint32_t>(*width),
                           static_cast<uint32_t>(*flags)});
      }
    }
    if (cursor != site.inputCount)
      return TALOS_RT_INVALID_BYTECODE;
  }
  TALOS_RT_CATCH(const std::bad_alloc &) { return TALOS_RT_OUT_OF_MEMORY; }
  TALOS_RT_CATCH(const std::length_error &) {
    return TALOS_RT_OUT_OF_RESOURCES;
  }
  auto *eventPlan =
      reinterpret_cast<talos_rt_computed_wait_record_v1 *>(record.data());
  if constexpr (Snapshot)
    return talos_rt_v1_event_snapshot_register(
        context, eventPlan, recordSize, *observerCodeUnit,
        samplerCaptures.data(), captureCount, targets.data(),
        static_cast<uint32_t>(targets.size()));
  else
    return talos_rt_v1_covergroup_clock_event_register(
        context, eventPlan, recordSize, static_cast<uint32_t>(*strobeValue),
        *observerCodeUnit, samplerCaptures.data(), captureCount);
}

} // namespace talos::designbytecode

#endif
