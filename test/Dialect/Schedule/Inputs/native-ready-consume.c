#include <assert.h>
#include <stdint.h>
#include <string.h>

// DirtyReadySetLayout for 262144 bits: leaves, 64 dirty words, one top word.
enum { LEAVES = 4096, DIRTY = 4096, TOP = 4160, WORDS = 4161 };
static uint64_t expected[WORDS];
uint64_t __talos_aot_model_ingress_v1[WORDS];
void consume(uint64_t);
void consume_structured(uint64_t, uint64_t);
void consume_global(uint64_t);

// Mark every nonempty leaf dirty, as the adds that filled it did. `stale`
// also leaves a dirty bit over an empty leaf, which a consume must keep.
static void index_words(uint64_t *words, unsigned stale) {
  for (unsigned i = 0; i < LEAVES; ++i)
    if (words[i] || i == stale) {
      words[DIRTY + i / 64] |= UINT64_C(1) << (i % 64);
      words[TOP] |= UINT64_C(1) << (i / 64);
    }
}
void observe(void) {
  assert(memcmp(__talos_aot_model_ingress_v1, expected, sizeof(expected)) == 0);
}
int main(void) {
  uint64_t *actual = __talos_aot_model_ingress_v1, *ready = actual;
  const uint64_t masks[] = {0, 1, 3, UINT64_C(1) << 63, UINT64_MAX};
  for (unsigned i = 0; i < 5; ++i)
    for (unsigned j = 0; j < 5; ++j)
      for (unsigned siblings = 0; siblings < 4; ++siblings) {
        memset(actual, 0, sizeof(expected));
        actual[0] = masks[i];
        actual[1] = siblings & 1;
        actual[64] = siblings & 2;
        index_words(actual, siblings == 3 ? 2 : LEAVES);
        memcpy(expected, actual, sizeof(expected));
        expected[0] &= ~masks[j];
        consume(masks[j]);
        // A second consume of the same mask must be harmless, even after
        // the last pending owner in a leaf has disappeared.
        consume(masks[j]);
        memcpy(actual, expected, sizeof(expected));
        actual[0] = masks[i];
        index_words(actual, LEAVES);
        memcpy(expected, actual, sizeof(expected));
        expected[0] &= ~masks[j];
        consume_structured(masks[j], 1);
        consume_structured(UINT64_MAX, 0);

        memset(ready, 0, sizeof(expected));
        ready[4095] = masks[i];
        ready[4094] = siblings & 1;
        ready[4031] = siblings & 2;
        index_words(ready, LEAVES);
        memcpy(expected, ready, sizeof(expected));
        expected[4095] &= ~masks[j];
        consume_global(masks[j]);
      }
  return 0;
}
