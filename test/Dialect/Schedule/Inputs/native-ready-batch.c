#include <assert.h>
#include <stdint.h>
#include <string.h>

// DirtyReadySetLayout for 262144 bits: leaves, 64 dirty words, one top word.
enum { LEAVES = 4096, DIRTY = 4096, TOP = 4160, WORDS = 4161 };
static uint64_t expected[WORDS];
uint64_t __talos_aot_model_ingress_v1[WORDS];
void exercise(uint64_t, uint64_t);

// The oracle's dirty bits: each leaf that received a nonempty add.
static void mark(uint64_t *words, unsigned leaf) {
  words[DIRTY + leaf / 64] |= UINT64_C(1) << (leaf % 64);
  words[TOP] |= UINT64_C(1) << (leaf / 64);
}
static void check(uint64_t *actual) {
  for (unsigned i = 0; i < WORDS; ++i)
    assert(actual[i] == expected[i]);
}
void observe(uint64_t *actual) {
  check(actual);
  actual[64] |= UINT64_C(1) << 60;
  mark(actual, 64);
  expected[64] = actual[64];
  mark(expected, 64);
}
int main(void) {
  uint64_t *actual = __talos_aot_model_ingress_v1;
  const uint64_t masks[] = {0, 1, UINT64_C(1) << 63, UINT64_MAX,
                            UINT64_C(0x5555555555555555)};
  for (unsigned i = 0; i < 5; ++i)
    for (unsigned j = 0; j < 5; ++j) {
      uint64_t a = masks[i], b = masks[j];
      memset(actual, 0, sizeof(expected));
      actual[64] = UINT64_MAX;
      actual[4095] = UINT64_MAX;
      actual[127] = 1; // Untouched sibling in a shared dirty word.
      mark(actual, 64);
      mark(actual, 4095);
      mark(actual, 127);
      memcpy(expected, actual, sizeof(expected));
      expected[0] = b;
      expected[63] = b;
      expected[64] &= ~a;
      expected[4095] = 0;
      // Word 0 received a, then b; its dirty bit may cover an empty leaf.
      if (a || b)
        mark(expected, 0);
      if (b)
        mark(expected, 63);
      exercise(a, b);
      expected[63] = 0;
      expected[4095] = a;
      if (a)
        mark(expected, 4095);
      check(actual);
    }
  return 0;
}
