//===- ProcessContext.h - Process runtime context locking -------*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_PROCESSCONTEXT_H
#define TALOS_RUNTIME_LIB_PROCESSCONTEXT_H

#include "ContextMutex.h"

#include <mutex>

struct talos_rt_context;

// The context whose mutex the current thread's generated AOT schedule holds
// (Process.cpp); runtime entries made from it skip the context lock.
extern thread_local talos_rt_context *lockedNativeAOTContext;

/// Locks `context`'s mutex and returns it. Out of line so that the common
/// generated-schedule entry (lock already held) stays an inline compare.
TalosContextMutex *lockProcessContext(talos_rt_context *context);

void initializeProcessContextLock(talos_rt_context *context,
                                  std::unique_lock<TalosContextMutex> &lock);

class ContextMutexLock {
public:
  explicit ContextMutexLock(talos_rt_context *context) {
    if (lockedNativeAOTContext != context)
      held = lockProcessContext(context);
  }
  ~ContextMutexLock() {
    if (held)
      held->unlock();
  }
  ContextMutexLock(const ContextMutexLock &) = delete;
  ContextMutexLock &operator=(const ContextMutexLock &) = delete;

private:
  TalosContextMutex *held = nullptr;
};

#endif // TALOS_RUNTIME_LIB_PROCESSCONTEXT_H
