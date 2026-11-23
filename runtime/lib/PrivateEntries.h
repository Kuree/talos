//===- PrivateEntries.h - Entries only generated code calls -----*- C++ -*-===//
//
// Runtime entries that generated code calls but the public headers do not
// declare. The compiler's native runtime catalog
// (include/talos/Dialect/Native/NativeRuntimeEntries.def) declares calls to
// them with its own prototypes; its build-time check
// (test/Support/NativeRuntimePrototypeTest.cpp) compares those with these.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_PRIVATEENTRIES_H
#define TALOS_RUNTIME_LIB_PRIVATEENTRIES_H

#include "talos/Runtime/Runtime.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Generated process spawns are already bound to a validated context. Reuse
// its immutable design-bytecode image while retaining the public standalone
// creation entry point for descriptors without a context.
talos_rt_status talos_rt_v1_process_instance_create_for_context(
    talos_rt_context *context, const talos_rt_process_descriptor_v1 *descriptor,
    talos_rt_process_instance_v1 **outInstance);

// Generated startup has validated its immutable reflection image.
talos_rt_status talos_rt_v1_context_create_embedded_read(
    const talos_rt_execution_descriptor_v1 *execution,
    talos_rt_context **outContext, uint64_t validatedChecksum,
    uint64_t validatedBits, uint32_t bindsNativePlanes);

// Only the generated closed executable's zero-initialized private planes.
talos_rt_status talos_rt_v1_native_state_initialize_bss(
    talos_rt_context *context, uint8_t *value, uint8_t *unknown,
    uint64_t bitCount, const talos_rt_native_state_fill_v1 *fills,
    uint64_t fillCount);

// Non-FIFO work that can invalidate an equal-value NBA capture.
uint32_t talos_rt_v1_eval_nba_runtime_pending(talos_rt_context *context,
                                              uint32_t state);

void talos_rt_v1_native_frame_store_wide(
    talos_rt_context *context, uint8_t *valuePlane, uint8_t *unknownPlane,
    uint64_t stateBits, uint64_t handle, uint32_t width, uint32_t flags,
    const uint8_t *value, const uint8_t *unknown);

// Generated constant Postponed VCD view table, valid for the model lifetime.
talos_rt_status talos_rt_v1_dump_bind_aliases(talos_rt_context *context,
                                              const uint64_t *rows,
                                              uint64_t count);

// Select the prepared clock's forwarding table. An observed alias keeps
// its original source writer and ordinary fanout on that run.
talos_rt_status talos_rt_v1_prepare_read_periodic(
    talos_rt_context *context, const talos_rt_native_schedule_node *nodes,
    uint32_t nodeCount, const talos_rt_native_periodic_clock_v1 *clocks,
    uint32_t clockCount, const talos_rt_native_periodic_alias_v1 *aliases,
    uint32_t aliasCount, uint64_t *nextEdges,
    talos_rt_native_periodic_control_v1 *control, uint32_t *useViews);
talos_rt_status talos_rt_v1_publish_read_clock(talos_rt_context *context,
                                               uint32_t actor, uint32_t state,
                                               uint64_t low, uint64_t oldValue,
                                               uint64_t newValue,
                                               uint32_t staticPublication);

// Compiler-generated immutable, sorted source actor IDs.
uint32_t talos_rt_v1_observed_writer_guard(talos_rt_context *context,
                                           const uint32_t *actors,
                                           uint64_t count);
uint32_t talos_rt_v1_observed_writer_guard_cached(talos_rt_context *context,
                                                  const uint32_t *actors,
                                                  uint64_t count,
                                                  uint64_t *cacheEntry,
                                                  uint64_t *epoch);
// Empty root sets are clean. Every nonempty root is queried even after
// rejection so diagnostic accounting remains exact.
uint32_t talos_rt_v1_static_specialization_guard_roots(
    talos_rt_context *context, const uint32_t *roots, uint64_t count);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // TALOS_RUNTIME_LIB_PRIVATEENTRIES_H
