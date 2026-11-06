#include "talos/Runtime/Runtime.h"

#include <cstdio>
#include <cstdlib>

static unsigned entries;

extern "C" void talos_test_native_task_entry() { ++entries; }

extern "C" void __real_talos_rt_v1_context_destroy(talos_rt_context *);

extern "C" void __wrap_talos_rt_v1_context_destroy(talos_rt_context *context) {
  // Virtual run, recursive method, exact super call and duplicate ref aliases
  // each cross the bytecode/native boundary. Static output may use fallback
  // when its automatic shadow cannot be represented as a native reference.
  if (entries < 4) {
    std::fprintf(stderr, "only %u native task entries observed\n", entries);
    std::abort();
  }
  std::puts("native task entries observed");
  __real_talos_rt_v1_context_destroy(context);
}
