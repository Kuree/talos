// Shared host/wasm32 probe for native and required-bytecode snapshot observers.
#ifndef TALOS_TEST_EVENTSNAPSHOTSMOKE_H
#define TALOS_TEST_EVENTSNAPSHOTSMOKE_H

#include "../../lib/ProcessPacking.h"
#include "../../lib/ProcessShared.h"
#include "../../lib/ProcessSignals.h"
#include "EventSnapshotBytecode.h"
#include <array>
#include <cstdio>

namespace talos::test {
inline uint32_t snapshotSmokeNativeCalls = 0;
inline talos_rt_status snapshotSmokeObserver(talos_rt_context *context,
                                             const uint64_t *captures,
                                             uint32_t captureCount,
                                             uint64_t *value, uint64_t *unknown,
                                             uint32_t limbs) {
  if (!context || !captures || captureCount != 1 || !value || !unknown)
    return TALOS_RT_INVALID_ARGUMENT;
  ++snapshotSmokeNativeCalls;
  uint64_t width = limbs == 1 ? 1 : 65;
  if (width == 65) {
    uint64_t mask = 0;
    auto status = talos_rt_v1_event_snapshot_mask(context, &mask);
    if (status != TALOS_RT_OK || mask != UINT64_MAX)
      return TALOS_RT_INVALID_DESIGN;
  }
  for (uint64_t bit = 0; bit != width; ++bit) {
    bool v = false, u = false;
    if (!talos_rt_read_clock_condition_publication_bit_unlocked(
            context, captures[0], bit, v, u) &&
        !talos_rt_read_signal_bit_unlocked(context, captures[0], bit, v, u,
                                           false))
      return TALOS_RT_INVALID_HANDLE;
    value[bit / 64] |= uint64_t{v} << (bit % 64);
    unknown[bit / 64] |= uint64_t{u} << (bit % 64);
  }
  return TALOS_RT_OK;
}

inline int runEventSnapshotSmoke(bool bytecode, bool maskedNBA = false,
                                 bool assign = false,
                                 bool twoStateRHS = false) {
  auto image = snapshotObserverBytecode();
  const talos_rt_observer_capture_abi_v1 primaryABI{
      TALOS_RT_OBSERVER_CAPTURE_STORAGE, 1};
  const talos_rt_observer_capture_abi_v1 samplerABI{
      TALOS_RT_OBSERVER_CAPTURE_STORAGE, 65};
  const std::array<talos_rt_observer_descriptor_v1, 2> observers{{
      {979, &primaryABI, 1, 1, TALOS_RT_OBSERVER_FOUR_STATE, 0,
       snapshotSmokeObserver, 0},
      {991, &samplerABI, 1, 65, TALOS_RT_OBSERVER_FOUR_STATE, 1,
       snapshotSmokeObserver, 0},
  }};
  talos_rt_execution_descriptor_v1 execution{};
  execution.version = TALOS_RT_VERSION;
  execution.flags = TALOS_RT_EXECUTION_HAS_BYTECODE |
                    (bytecode ? TALOS_RT_EXECUTION_REQUIRE_BYTECODE : 0);
  execution.bytecode = image.data();
  execution.bytecode_size = image.size();
  execution.checksum = snapshotImageChecksum(image);
  execution.state_bit_count = 256;
  execution.observers = observers.data();
  execution.observer_count = observers.size();
  talos_rt_context *context = nullptr;
  auto status = talos_rt_v1_context_create_for_design(&execution, &context);
  if (status != TALOS_RT_OK) {
    std::fprintf(stderr, "snapshot smoke context: %u\n", status);
    return 1;
  }
  struct Cleanup {
    talos_rt_context *context;
    ~Cleanup() {
      context->scheduledProcesses.clear();
      context->scheduledProcessIndices.clear();
      context->nativeStateValue = nullptr;
      context->nativeStateUnknown = nullptr;
      context->nativeStateBitCount = 0;
      talos_rt_v1_context_destroy(context);
    }
  } cleanup{context};
  std::array<uint64_t, 4> nativeValue{}, nativeUnknown{};
  std::fill(context->stateUnknown.begin(), context->stateUnknown.end(), 0);
  context->nativeStateValue = reinterpret_cast<uint8_t *>(nativeValue.data());
  context->nativeStateUnknown =
      reinterpret_cast<uint8_t *>(nativeUnknown.data());
  context->nativeStateBitCount = 256;
  const uint64_t data = UINT64_C(0xfedcba9876543210) | (maskedNBA ? 1 : 0);
  const uint64_t unknown = twoStateRHS ? 0 : UINT64_C(0x80000000000000f0);
  storePackedBits(context->stateValue, 16, 64, data);
  storePackedBits(context->stateUnknown, 16, 64, unknown);
  storePackedBits(context->stateValue, 80, 1, 1);
  storePackedBits(context->stateUnknown, 80, 1, 1);
  // Native generated storage may already contain later source stores. Pure
  // samplers must use the publication image for every captured root (IEEE
  // 1801-2018 6.50), even when the triggering control is a different root.
  storePackedBits(nativeValue, 16, 64, UINT64_C(0x2222222222222222));
  if (maskedNBA) {
    // IEEE 1800-2023 10.6/10.4.2 and IEEE 1801-2018 6.50: the NBA raises
    // bit zero, while a force/assign preserves the 65th bit as Z. The raw
    // RHS has zero there; a save must capture the committed signal instead.
    storePackedBits(context->stateValue, 16, 64, 0);
    storePackedBits(context->stateUnknown, 16, 64, 0);
    storePackedBits(nativeValue, 16, 64, 0);
    storePackedBits(nativeUnknown, 16, 64, 0);
    storePackedBits(nativeValue, 80, 1, 1);
    storePackedBits(nativeUnknown, 80, 1, 1);
    auto &mask = assign ? context->assignMask : context->forceMask;
    mask.assign(4, 0);
    storePackedBits(mask, 80, 1, 1);
  }
  if (talos_rt_v1_native_state_register_static(context, 7, 96, 65) !=
      TALOS_RT_OK)
    return 2;
  talos_rt_process_descriptor_v1 descriptor{};
  descriptor.execution = &execution;
  talos_rt_process_instance_v1 instance{};
  instance.descriptor = &descriptor;
  instance.context = context;
  instance.tier = bytecode ? TALOS_RT_TIER_BYTECODE : TALOS_RT_TIER_NATIVE;
  context->scheduledProcesses.emplace_back();
  auto &process = context->scheduledProcesses.back();
  process.instance = &instance;
  process.token = 1;
  process.started = true;
  process.suspendKind = TALOS_RT_SUSPEND_FOREVER;
  context->scheduledProcessIndices.emplace(1, 0);
  context->activeNativeProcess = &instance;
  context->activeLogicalProcessToken = TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG | 1;
  struct Plan {
    talos_rt_computed_wait_record_v1 wait;
    std::array<talos_rt_computed_observer_v1, 64> observers;
    std::array<talos_rt_computed_capture_v1, 64> captures;
    std::array<talos_rt_computed_dependency_v1, 64> dependencies;
    std::array<talos_rt_computed_clause_v1, 64> clauses;
    std::array<std::array<uint64_t, 2>, 64> previous;
  } plan{};
  plan.wait = {TALOS_RT_VERSION,
               TALOS_RT_SUSPEND_OBSERVER,
               TALOS_RT_COMPUTED_WAIT_INTERLEAVED,
               64,
               64,
               64,
               64,
               64,
               offsetof(Plan, observers),
               offsetof(Plan, captures),
               offsetof(Plan, dependencies),
               offsetof(Plan, clauses),
               offsetof(Plan, previous),
               0,
               sizeof(Plan),
               0};
  for (uint32_t index = 0; index != 64; ++index) {
    plan.observers[index] = {
        979, index,
        1,   index,
        1,   static_cast<uint32_t>(offsetof(Plan, previous) + index * 16),
        0};
    plan.captures[index].stable_id = maskedNBA ? 16 : 0;
    plan.dependencies[index] = {maskedNBA ? 16u : 0u,
                                TALOS_RT_OBSERVER_DEPENDENCY_SIGNAL, 1};
    plan.clauses[index] = {index, TALOS_RT_OBSERVER_CONDITION_NONE,
                           TALOS_RT_WAIT_EDGE_POSEDGE, 0};
  }
  const talos_rt_computed_capture_v1 capture{16, 0, 0, 0};
  const talos_rt_event_snapshot_target_v1 target{
      talos_rt_v1_native_state_static_handle(7), 65,
      TALOS_RT_EVENT_SNAPSHOT_FOUR_STATE};
  if constexpr (sizeof(void *) == 4) {
    // Counts must be rejected before dereferencing these intentionally short
    // arrays on wasm32. No host-sized pointer is encoded in a target record.
    if (talos_rt_v1_event_snapshot_register(
            context, &plan.wait, sizeof(plan), 991, &capture, 1, &target,
            UINT32_MAX) != TALOS_RT_INVALID_ARGUMENT ||
        talos_rt_v1_event_snapshot_register(context, &plan.wait, sizeof(plan),
                                            991, &capture, UINT32_MAX, &target,
                                            1) != TALOS_RT_INVALID_ARGUMENT)
      return 7;
  }
  status = talos_rt_v1_event_snapshot_register(
      context, &plan.wait, sizeof(plan), 991, &capture, 1, &target, 1);
  if (status != TALOS_RT_OK)
    return 2;
  context->activeNativeProcess = nullptr;
  context->activeLogicalProcessToken = 0;
  snapshotSmokeNativeCalls = 0;
  const uint8_t zero = 0, one = 1;
  if (maskedNBA) {
    std::array<uint8_t, 9> value{}, unknownPlane{};
    storePackedBytes(value.data(), 0, 64, data);
    storePackedBytes(unknownPlane.data(), 0, 64, unknown);
    status = talos_rt_v1_scheduler_nba(
        context, reinterpret_cast<uint8_t *>(nativeValue.data()),
        twoStateRHS ? nullptr
                    : reinterpret_cast<uint8_t *>(nativeUnknown.data()),
        256, 16, 65, 0, value.data(),
        twoStateRHS ? nullptr : unknownPlane.data());
    if (status != TALOS_RT_OK ||
        talos_rt_v1_scheduler_run(context) != TALOS_RT_OK)
      return 8;
    if (!context->exactEvents || context->exactEvents->snapshots.size() != 1)
      return 9;
  } else {
    talos_rt_v1_scheduler_signal_transition(context, 0, 1, &zero, nullptr, &one,
                                            nullptr);
  }
  if (context->schedulerStatus != TALOS_RT_OK ||
      talos_rt_v1_event_snapshot_flush(context) != TALOS_RT_OK)
    return 3;
  if ((bytecode && snapshotSmokeNativeCalls != 0) ||
      (!bytecode && snapshotSmokeNativeCalls == 0))
    return 4;
  if (loadPackedBits(context->stateValue, 96, 64) != data ||
      loadPackedBits(context->stateUnknown, 96, 64) != unknown ||
      loadPackedBits(context->stateValue, 160, 1) != 1 ||
      loadPackedBits(context->stateUnknown, 160, 1) != 1 ||
      loadPackedBits(nativeValue, 96, 64) != data ||
      loadPackedBits(nativeUnknown, 96, 64) != unknown)
    return 5;
  talos_rt_unregister_exact_events_unlocked(
      context, TALOS_RT_NATIVE_LOGICAL_PROCESS_TAG | UINT64_C(1));
  return context->exactEvents ? 6 : 0;
}
} // namespace talos::test
#endif
