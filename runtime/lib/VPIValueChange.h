//===- VPIValueChange.h - Private callback publication fences ----*- C++
//-*-===//
#ifndef TALOS_RUNTIME_VPI_VALUE_CHANGE_H
#define TALOS_RUNTIME_VPI_VALUE_CHANGE_H

#include "talos/Runtime/Runtime.h"
#include <memory>
#include <vector>

struct SignalSubscription;

// Caller holds the context mutex. Register a packed-root watch in the existing
// signal index without creating a SystemVerilog process or wait record.
bool talos_rt_register_vpi_signal_subscription_unlocked(
    talos_rt_context *context, uint64_t stableID, uint64_t width,
    uint64_t alias,
    std::vector<std::unique_ptr<SignalSubscription>> &subscriptions);

// Called only for a matching VPI subscription, after both canonical planes
// commit. Capture a snapshot and arrange an observer fence; never run client
// code while a signal bucket is being traversed.
bool talos_rt_vpi_capture_change_unlocked(talos_rt_context *context,
                                          uint64_t alias);

// After all synchronous HDL observers have sampled a coherent publication.
// During an application VPI call/callback/import, keep the change queued.
bool talos_rt_vpi_deliver_changes_unlocked(talos_rt_context *context);

// Explicit simulator return from a foreign application routine, before HDL
// resumes. This is not a vpi_put_value exit hook.
bool talos_rt_vpi_client_returned_unlocked(talos_rt_context *context);

// Delivers the changes a returning foreign import caused, before HDL resumes
// (IEEE 1800-2023 35.5.3, 38.36.1). Requires a VPI-enabled context; takes the
// context mutex only when a change is pending.
talos_rt_status talos_rt_vpi_after_client_return(talos_rt_context *context,
                                                 talos_rt_status status);

#endif
