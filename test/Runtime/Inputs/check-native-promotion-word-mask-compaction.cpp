#include "talos/Runtime/Runtime.h"

#include <cassert>
#include <cstdint>
#include <cstring>
#include <initializer_list>

extern "C" {
uint32_t __talos_eval_group_promotion_ready_v1_i32(uint64_t);
void __talos_eval_promotion_invalidate_range_v1(uint64_t, uint64_t);
void __talos_eval_promotion_recheck_range_v1(uint64_t, uint64_t);
uint64_t *compaction_test_unknown();
uint8_t *compaction_test_latches();
}

// IEEE 1800-2023 6.3.1: every required bit must be 0/1; unrelated X/Z
// bits must neither prevent promotion nor be overwritten by the query.
static bool required(unsigned domain, unsigned bit) {
  switch (domain) {
  case 0:
    return bit == 0 || bit == 8 || bit == 16;
  case 1:
    return (bit >= 63 && bit < 1048576) || bit == 1048584;
  default:
    return bit == 0 || bit == 128;
  }
}

int main() {
  auto *unknown = compaction_test_unknown();
  auto *latches = compaction_test_latches();
  constexpr unsigned words = 16386;
  // Exhaust both small domains, every boundary bit, and distant positions
  // throughout the long interior. The scalar oracle does not read scan tables.
  unsigned bits[640], bitCount = 0;
  for (unsigned bit = 0; bit != 193; ++bit)
    bits[bitCount++] = bit;
  for (unsigned bit = 1048448; bit != words * 64; ++bit)
    bits[bitCount++] = bit;
  for (unsigned bit = 256; bit < 1048448; bit += 16381)
    bits[bitCount++] = bit;
  uint64_t snapshot[words];
  auto check = [&] {
    std::memcpy(snapshot, unknown, sizeof(snapshot));
    for (unsigned domain = 0; domain != 3; ++domain) {
      bool expected = true;
      for (unsigned i = 0; i != bitCount; ++i) {
        unsigned bit = bits[i];
        if (required(domain, bit) &&
            (unknown[bit / 64] & (uint64_t{1} << (bit % 64))))
          expected = false;
      }
      assert(__talos_eval_group_promotion_ready_v1_i32(domain) == expected);
      assert((latches[domain] == TALOS_RT_PROMOTION_LATCH_KNOWN) == expected);
    }
    assert(std::memcmp(snapshot, unknown, sizeof(snapshot)) == 0);
  };
  auto write = [&](unsigned bit, bool x) {
    uint64_t mask = uint64_t{1} << (bit % 64);
    if (x) {
      unknown[bit / 64] |= mask;
      __talos_eval_promotion_invalidate_range_v1(bit, 1);
    } else {
      unknown[bit / 64] &= ~mask;
      __talos_eval_promotion_recheck_range_v1(bit, 1);
    }
  };
  check();
  // Move an unknown bit across single words, full runs and holes. Each
  // clearing forces an old exact hint to resume the complete proof.
  for (unsigned i = 0; i != bitCount; ++i) {
    unsigned bit = bits[i];
    write(bit, true);
    check();
    check();
    write(bit, false);
    check();
  }
  // Unknown neighbors outside every certificate remain present together.
  for (unsigned i = 0; i != bitCount; ++i) {
    unsigned bit = bits[i];
    if (!required(0, bit) && !required(1, bit) && !required(2, bit))
      write(bit, true);
  }
  check();
  // Recovery of one hinted word must not hide an unknown in another word,
  // including an earlier word than the hint and the last partial word.
  for (unsigned bit : {63u, 1048584u})
    write(bit, true);
  check();
  write(63, false);
  check();
  write(64, true);
  write(1048584, false);
  check();
  // Context reuse clears positive proofs but may retain exact word hints.
  std::memset(latches, 0, 3);
  std::memset(unknown, 0, words * sizeof(uint64_t));
  unknown[16383] = uint64_t{1} << 63;
  check();
  write(1048575, false);
  check();
}
