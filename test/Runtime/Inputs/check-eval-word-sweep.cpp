#include "talos/Runtime/EvalNBAQueue.h"
#include "talos/Runtime/ReadySet.h"
#include "talos/Runtime/Runtime.h"
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>

// asm labels are final symbol names; Mach-O prefixes C symbols with '_'.
#define TALOS_TEST_STRINGIFY_(text) #text
#define TALOS_TEST_STRINGIFY(text) TALOS_TEST_STRINGIFY_(text)
#define TALOS_TEST_SYMBOL(name) TALOS_TEST_STRINGIFY(__USER_LABEL_PREFIX__) name

extern "C" {
extern uint64_t __talos_aot_model_ingress_v1[];
extern uint32_t *__talos_periodic_termination_v1;
int word0(talos_rt_context *,
          bool *) asm(TALOS_TEST_SYMBOL("__talos_eval_dispatch_v1.word_0"));
int word2(talos_rt_context *,
          bool *) asm(TALOS_TEST_SYMBOL("__talos_eval_dispatch_v1.word_2"));
int __talos_eval_dispatch_v1(void *, talos_rt_context *);
#ifdef ORDERED_NBA
extern talos::runtime::EvalNBAQueue __talos_eval_ordered_nba_queue_v1;
int model_main(int, char **);
#endif
}

int main() {
  talos_rt_context *context = nullptr;
  assert(talos_rt_v1_context_create(&context) == TALOS_RT_OK);
  auto *ingress = __talos_aot_model_ingress_v1;
#ifdef ORDERED_NBA
  const talos::runtime::DirtyReadySetLayout layout(133);
#else
  const talos::runtime::DirtyReadySetLayout layout(130);
#endif
  talos::runtime::DirtyReadySetView ready(ingress, layout);
  const uint64_t dirty = layout.offsets[1];
  bool fallback = false;
  auto reset = [&] {
    std::fill_n(ingress, layout.storageWords, uint64_t{0});
    __talos_periodic_termination_v1 = nullptr;
    fallback = false;
  };

#ifdef ORDERED_NBA
  // Model a queue failure recorded by the just-executed owner. Even though
  // another owner is ready in the same word, return before executing it and
  // let the coordinator propagate the exact status without committing NBAs.
  reset();
  ready.set(0);
  ready.set(1);
  auto &queue = __talos_eval_ordered_nba_queue_v1;
  queue.error = TALOS_RT_OUT_OF_RESOURCES;
  assert(word0(context, &fallback) == TALOS_RT_OUT_OF_RESOURCES);
  assert(!ready.test(0) && ready.test(1));
  assert(__talos_eval_dispatch_v1(nullptr, context) ==
         TALOS_RT_OUT_OF_RESOURCES);
  assert(ready.test(1) && queue.size == 0);
  // The pending owner keeps its word's dirty bit.
  assert(ingress[dirty] & 1);
  queue.error = TALOS_RT_OK;
  std::puts("ordered NBA error handoff passed");
#else
  // Both real owners in the partial last word run in one call.
  reset();
  ready.set(128);
  ready.set(129);
  assert(word2(context, &fallback) == TALOS_RT_OK);
  assert(!ready.test(128) && !ready.test(129));

  // A word runs its ranked group and every pending direct owner in rank
  // order, and consumes each one. Dirty bits are left to the coordinator.
  reset();
  ready.set(0);
  ready.set(1);
  ready.set(2);
  ready.set(63);
  ready.set(64);
  assert(word0(context, &fallback) == TALOS_RT_OK);
  assert(ingress[0] == 0 && ready.test(64));
  assert(ingress[dirty] == 3);

  // A stop request ends the word after the current owner, even when the next
  // ready owner is in the same word.
  reset();
  uint32_t stopping = 1;
  __talos_periodic_termination_v1 = &stopping;
  ready.set(1);
  ready.set(2);
  assert(word0(context, &fallback) == TALOS_RT_TIER_UNAVAILABLE);
  assert(!ready.test(1) && ready.test(2));

  // The coordinator returns the same status and keeps the word's dirty bit,
  // so the remaining owner is found when the generated loop resumes.
  reset();
  __talos_periodic_termination_v1 = &stopping;
  ready.set(1);
  ready.set(2);
  assert(__talos_eval_dispatch_v1(nullptr, context) ==
         TALOS_RT_TIER_UNAVAILABLE);
  assert(!ready.test(1) && ready.test(2) && (ingress[dirty] & 1));

  // A stale dirty bit over an empty word is cleared on the way to the next
  // dirty word, whose owner then runs.
  reset();
  __talos_periodic_termination_v1 = &stopping;
  ingress[dirty] |= 2;
  ready.set(128);
  ready.set(129);
  assert(__talos_eval_dispatch_v1(nullptr, context) ==
         TALOS_RT_TIER_UNAVAILABLE);
  assert(!ready.test(128) && ready.test(129));
  assert(ingress[dirty] == 4);
  __talos_periodic_termination_v1 = nullptr;
  std::puts("word sweep selection and handoffs passed");
#endif
  talos_rt_v1_context_destroy(context);
#ifdef ORDERED_NBA
  // Execute the complete MLIR model as well: the wide NBA root makes a
  // 0 -> 1 -> 0 round trip and its posedge observer must still fire.
  reset();
  char name[] = "segmented-ordered-nba";
  char *argv[] = {name, nullptr};
  assert(model_main(1, argv) == 0);
#endif
}
