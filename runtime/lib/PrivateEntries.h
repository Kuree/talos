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

// Compiler-private ABI. Empty root sets are clean; every nonempty root is
// queried even after rejection so diagnostic accounting remains exact.
uint32_t talos_rt_v1_static_specialization_guard_roots(
    talos_rt_context *context, const uint32_t *roots, uint64_t count);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // TALOS_RUNTIME_LIB_PRIVATEENTRIES_H
