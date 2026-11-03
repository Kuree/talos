//===- ProcessValidation.h - Process ABI validation helpers -----*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_PROCESSVALIDATION_H
#define TALOS_RUNTIME_LIB_PROCESSVALIDATION_H

#include "talos/Runtime/Runtime.h"

#include <cstdint>
#include <memory>

struct ScheduledProcess;

namespace talos::process {

talos_rt_status
validateTableProcess(const talos_rt_process_descriptor_v1 &descriptor);

constexpr uint64_t kWaitHeaderSize = sizeof(talos_rt_wait_record_v1);
constexpr uint64_t kWaitEntrySize = sizeof(talos_rt_wait_entry_v1);

bool addOverflow(uint64_t lhs, uint64_t rhs, uint64_t &result);
bool alignUp(uint64_t value, uint64_t alignment, uint64_t &result);
uint64_t layoutChecksum(const talos_rt_frame_layout_v1 &layout);
bool validContinuation(const talos_rt_frame_layout_v1 &layout,
                       uint32_t continuation);
/// The wait field at `offset` of a layout accepted by validateLayout.
const talos_rt_frame_field_v1 *
findWaitField(const talos_rt_frame_layout_v1 &layout, uint64_t offset);
talos_rt_status
validateDescriptor(const talos_rt_process_descriptor_v1 &descriptor,
                   talos_rt_context *context, uint64_t &nativeSize,
                   uint64_t &nativeAlignment, uint64_t &scratchOffset,
                   uint64_t &scratchSize);
/// The last suspension validateAction accepted for one process instance
/// (two-tier B2 Q6). Wait validation is a pure function of the action, the
/// wait record's bytes in the frame and the instance's immutable descriptor,
/// so a process that suspends again at the same wait with a byte-identical
/// record skips it. Observer waits and records above kMaxBytes always
/// validate in full. A process that keeps missing (it alternates waits, or
/// its record changes each time) stops filling after kMissLimit fills in a
/// row, so it pays only one test per suspension.
struct ValidatedSuspension {
  static constexpr uint64_t kMaxBytes = 96;
  static constexpr uint8_t kMissLimit = 4;
  bool valid = false;
  bool bytecode = false;
  bool disabled = false;
  uint8_t fillsWithoutHit = 0;
  talos_rt_suspend_kind kind = TALOS_RT_SUSPEND_NONE;
  uint32_t continuation = 0;
  uint32_t flags = 0, validatedFlags = 0;
  uint64_t payload = 0, auxiliary = 0, validatedAuxiliary = 0;
  uint8_t record[kMaxBytes] = {};
};
/// `cache` (optional) holds the instance's ValidatedSuspension, allocated on
/// its first cacheable suspension; an allocation failure only skips caching.
talos_rt_status
validateAction(talos_rt_process_instance_v1 &instance,
               talos_rt_fragment_action_v1 &action, bool bytecode,
               std::unique_ptr<ValidatedSuspension> *cache = nullptr);
const talos_rt_wait_record_v1 *currentWait(const ScheduledProcess &process);
// The start record of a virtual owner (TALOS_RT_SPAWN_VIRTUAL) that has no
// frame yet, else null.
const talos_rt_process_start_v1 *
virtualOwnerStart(const talos_rt_process_instance_v1 *instance);
const talos_rt_wait_entry_v1 *waitEntries(const talos_rt_wait_record_v1 *wait);
const talos_rt_observer_descriptor_v1 *
findObserverDescriptor(const talos_rt_execution_descriptor_v1 *execution,
                       uint64_t codeUnitID);

template <typename T>
const T *computedWaitSpan(const talos_rt_computed_wait_record_v1 *wait,
                          uint64_t offset, uint64_t count) {
  if (!wait || offset > wait->total_size ||
      count > (wait->total_size - offset) / sizeof(T))
    return nullptr;
  return reinterpret_cast<const T *>(reinterpret_cast<const uint8_t *>(wait) +
                                     offset);
}

template <typename T>
T *computedWaitSpan(talos_rt_computed_wait_record_v1 *wait, uint64_t offset,
                    uint64_t count) {
  return const_cast<T *>(computedWaitSpan<T>(
      static_cast<const talos_rt_computed_wait_record_v1 *>(wait), offset,
      count));
}

} // namespace talos::process

#endif // TALOS_RUNTIME_LIB_PROCESSVALIDATION_H
