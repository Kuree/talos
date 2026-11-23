//===- ExceptionSupport.h - Optional runtime exception guards -*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_EXCEPTIONSUPPORT_H
#define TALOS_RUNTIME_LIB_EXCEPTIONSUPPORT_H

#include <cstdio>
#include <cstdlib>
#include <new>

// Preserve the native runtime's status-based allocation failure handling. The
// wasm runtime is compiled with -fno-exceptions and a noexcept libc++, so
// explicitly detected unrepresentable allocations follow the same fatal path
// as allocator failures there.
[[noreturn]] inline void talos_rt_out_of_memory() {
#if !defined(TALOS_RT_IGNORE_EXCEPTIONS) &&                                    \
    (defined(__cpp_exceptions) || defined(_CPPUNWIND))
  throw std::bad_alloc();
#else
  std::fputs("talos runtime: out of memory\n", stderr);
  std::abort();
#endif
}

// Keep exception translation at native C ABI boundaries without requiring
// exception support in the wasm runtime. In the exception-free build the
// guarded body executes directly and handler bodies are unreachable.
#if defined(__cpp_exceptions) || defined(_CPPUNWIND)
#define TALOS_RT_TRY try
#define TALOS_RT_CATCH(...) catch (__VA_ARGS__)
#define TALOS_RT_CATCH_ALL catch (...)
#define TALOS_RT_RETHROW throw
#else
#define TALOS_RT_TRY if (true)
#define TALOS_RT_CATCH(...) else if (false)
#define TALOS_RT_CATCH_ALL else if (false)
#define TALOS_RT_RETHROW std::abort()
#endif

#endif // TALOS_RUNTIME_LIB_EXCEPTIONSUPPORT_H
