//===- ContextMutex.h - Re-entrant context lock with inline re-entry ------===//
//
// A recursive mutex for the runtime context. The context lock is re-entered
// on almost every runtime entry made from code that already holds it (the
// interpreter, publication, scheduler helpers), and std::recursive_mutex
// pays a libc call for each re-entry. This lock keeps the owning thread's tag
// and a depth next to a plain std::mutex, so re-entry is an inline compare and
// increment (two-tier B2 Q1).
//
// Mutual exclusion is the std::mutex's. The owner tag is written only by the
// thread holding that mutex; another thread can read its own tag there only
// after it has acquired the mutex itself, so relaxed accesses suffice. The
// depth is touched only by the owner.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_CONTEXTMUTEX_H
#define TALOS_RUNTIME_LIB_CONTEXTMUTEX_H

#include <atomic>
#include <cstdint>
#include <mutex>

#if defined(__GNUC__) || defined(__clang__)
#define TALOS_CONTEXT_MUTEX_NOINLINE __attribute__((noinline))
#elif defined(_MSC_VER)
#define TALOS_CONTEXT_MUTEX_NOINLINE __declspec(noinline)
#else
#define TALOS_CONTEXT_MUTEX_NOINLINE
#endif

class TalosContextMutex {
public:
  TalosContextMutex() = default;
  TalosContextMutex(const TalosContextMutex &) = delete;
  TalosContextMutex &operator=(const TalosContextMutex &) = delete;

  // Only the re-entry check and the depth step are inline; acquiring and
  // releasing the underlying mutex stay out of line so every caller keeps a
  // small inline body (the first acquisition costs what a libc call cost).
  void lock() {
    if (owner.load(std::memory_order_relaxed) == threadTag()) {
      ++depth;
      return;
    }
    acquire();
  }

  bool try_lock() {
    if (owner.load(std::memory_order_relaxed) == threadTag()) {
      ++depth;
      return true;
    }
    return tryAcquire();
  }

  void unlock() {
    if (--depth == 0)
      release();
  }

private:
  // One tag per thread in the program: the runtime is a static library, so
  // this function-local thread_local has one instance. A lock shared across
  // shared-library boundaries would need a single exported tag instead.
  static const void *threadTag() {
    static thread_local char tag;
    return &tag;
  }

  TALOS_CONTEXT_MUTEX_NOINLINE void acquire() {
    impl.lock();
    owner.store(threadTag(), std::memory_order_relaxed);
    depth = 1;
  }

  TALOS_CONTEXT_MUTEX_NOINLINE bool tryAcquire() {
    if (!impl.try_lock())
      return false;
    owner.store(threadTag(), std::memory_order_relaxed);
    depth = 1;
    return true;
  }

  TALOS_CONTEXT_MUTEX_NOINLINE void release() {
    owner.store(nullptr, std::memory_order_relaxed);
    impl.unlock();
  }

  std::mutex impl;
  std::atomic<const void *> owner{nullptr};
  uint32_t depth = 0;
};

#endif // TALOS_RUNTIME_LIB_CONTEXTMUTEX_H
