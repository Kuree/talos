#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" int model_main(int, char **);
extern "C" uint64_t __talos_test_ranked_executions[];
extern "C" uint8_t __talos_state_value[], __talos_state_unknown[];
extern "C" uint64_t __talos_aot_model_ingress_v1[];
extern "C" int32_t *__talos_periodic_termination_v1;
extern "C" int32_t __talos_eval_dispatch_v1(void *, void *);
extern "C" void __talos_eval_promotion_invalidate_v1();

int main(int argc, char **argv) {
  int status = model_main(argc, argv);
  // Startup retains the original actor entries. For two later input changes,
  // the small SCC needs two finite
  // sweeps for each change. Its 32 siblings must execute only once per
  // change, even though they share the source and its dependency island.
  const uint64_t expected[] = {0, 4, 2, 2};
  for (unsigned block = 0; block != 4; ++block)
    if (__talos_test_ranked_executions[block] != expected[block]) {
      std::fprintf(stderr, "block %u: executions=%llu expected=%llu\n", block,
                   (unsigned long long)__talos_test_ranked_executions[block],
                   (unsigned long long)expected[block]);
      std::abort();
    }
  std::puts("selective sweeps: feedback=4 acyclic=2 retries=2");
  // Force another backward event, with a termination latch visible at the
  // return from the finite feedback sweep. No unrelated block may run and
  // the backward activation must still be pending when the dispatcher stops.
  std::memset(__talos_state_value, 0, 38);
  std::memset(__talos_state_unknown, 0, 38);
  __talos_state_value[1] = 1;
  __talos_eval_promotion_invalidate_v1();
  __talos_aot_model_ingress_v1[0] = 6;
  int32_t stop = 1;
  __talos_periodic_termination_v1 = &stop;
  auto feedback = __talos_test_ranked_executions[1];
  auto cone = __talos_test_ranked_executions[3];
  __talos_eval_dispatch_v1(nullptr, nullptr);
  if (__talos_test_ranked_executions[1] != feedback + 1 ||
      __talos_test_ranked_executions[3] != cone ||
      __talos_aot_model_ingress_v1[0] != (2 | 8))
    std::abort();
  __talos_periodic_termination_v1 = nullptr;
  std::puts("termination polled between affected sweeps");
  return status;
}
