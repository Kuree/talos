#include "talos/Runtime/ReadySet.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>

using talos::runtime::DirtyReadySetLayout;
using talos::runtime::DirtyReadySetView;
extern "C" {
#define MERGE(N) void merge_##N(uint64_t *);
MERGE(1)
MERGE(63)
MERGE(64)
MERGE(65)
MERGE(128)
MERGE(1023)
MERGE(1024)
MERGE(1216)
MERGE(2048)
MERGE(2049)
MERGE(4096)
MERGE(7553)
MERGE(262145)
#undef MERGE
// The ready set every merge names, with room after the largest layout for
// suffix canaries and a separate source.
enum { FRAME = 8400 };
uint64_t __talos_aot_model_ingress_v1[FRAME];
uint64_t merge_observed(uint64_t *);
void ready_merge_observe(uint64_t *base) {
  // Both leaves received work, so both dirty bits are set.
  if (base[0] != 3 || base[1] != 4 || base[2] != 3)
    std::abort();
  // The later ready update must observe the callback's changes.
  base[0] = 0;
  base[1] = 16;
}
}

struct Test {
  uint32_t capacity;
  void (*merge)(uint64_t *);
};

int main() {
  const Test tests[] = {
#define MERGE(N) {N, merge_##N},
      MERGE(1) MERGE(63) MERGE(64) MERGE(65) MERGE(128) MERGE(1023) MERGE(1024)
          MERGE(1216) MERGE(2048) MERGE(2049) MERGE(4096) MERGE(7553)
              MERGE(262145)
#undef MERGE
  };
  uint64_t *base = __talos_aot_model_ingress_v1;
  for (auto test : tests) {
    const DirtyReadySetLayout layout(test.capacity);
    const size_t frame = 2 * layout.storageWords + 7;
    if (frame > FRAME)
      return 3;
    // Suffix canaries also provide valid overlapping source ranges. The set is
    // a named global, so no source range precedes it.
    for (unsigned mode = 0; mode != 4; ++mode)
      for (unsigned overlap : {0u, 1u, 2u, 3u}) {
        std::fill(base, base + frame, UINT64_C(0xfeedfacefeedface));
        std::fill(base, base + layout.storageWords, 0);
        DirtyReadySetView initial(base, layout);
        if (mode >= 2) {
          // Existing leaves and dirty bits, including the 63/64 and
          // 4095/4096 word boundaries.
          for (uint32_t word = mode == 3 ? 1 : 0; word < layout.counts[0];
               word += 67)
            initial.setWord(word, 1);
          for (uint32_t word : {63, 64, 4095, 4096})
            initial.setWord(word, 2);
        }
        // A stale dirty bit over an empty leaf stays until a reader clears it.
        if (mode == 3 && layout.hasSummaries())
          base[layout.offsets[1]] |= 1;
        size_t source = layout.storageWords + 1;
        for (uint32_t word = 0; word < layout.counts[0]; ++word)
          base[source + word] = mode == 0 || mode == 3 ? 0
                                : mode == 1 ? (word % 71 == 0 ? UINT64_MAX : 0)
                                            : UINT64_MAX;
        if (overlap == 1)
          source = 0; // source == destination
        if (overlap == 2)
          source = 1; // A later source read can observe updated leaves.
        if (overlap == 3)
          source = 2; // A later source read can observe updated dirty bits.
        std::vector<uint64_t> expected(base, base + frame);
        DirtyReadySetView reference(expected.data(), layout);
        for (uint32_t word = 0; word < layout.counts[0]; ++word)
          reference.setWord(word, expected[source + word]);
        test.merge(base + source);
        if (!std::equal(expected.begin(), expected.end(), base)) {
          std::fprintf(stderr, "capacity=%u mode=%u overlap=%u\n",
                       test.capacity, mode, overlap);
          return 1;
        }
      }
  }
  std::fill(base, base + 3, 0);
  base[2] = 2;
  uint64_t source[] = {2, 4};
  if (merge_observed(source) != 24 || base[0] != 0 || base[1] != 24 ||
      base[2] != 3)
    return 2;
}
