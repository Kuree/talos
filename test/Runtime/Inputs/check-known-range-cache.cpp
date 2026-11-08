#include <cassert>
#include <cstdint>

extern "C" {
uint8_t *test_range_cache();
void __talos_eval_promotion_invalidate_range_v1(uint64_t, uint64_t);
void __talos_eval_promotion_recheck_range_v1(uint64_t, uint64_t);
void __talos_eval_promotion_invalidate_v1();
}

int main() {
  auto *cache = test_range_cache();
  assert(*cache == 0);
  for (unsigned bit = 0; bit != 64; ++bit) {
    bool watched = (bit >= 1 && bit <= 3) || bit == 8;
    *cache = 1;
    __talos_eval_promotion_invalidate_range_v1(bit, 1);
    assert(*cache == unsigned(!watched));
    __talos_eval_promotion_recheck_range_v1(bit, 1);
    assert(*cache == unsigned(!watched));
    *cache = 0;
    __talos_eval_promotion_recheck_range_v1(bit, 1);
    assert(*cache == 0); // a gain requests no new positive proof
    *cache = 1;
    __talos_eval_promotion_recheck_range_v1(bit, 1);
    assert(*cache == 1); // known bits becoming known again cannot break it
  }
  *cache = 1;
  __talos_eval_promotion_invalidate_v1();
  assert(*cache == 0);
  *cache = 1;
  __talos_eval_promotion_invalidate_range_v1(0, 9);
  assert(*cache == 0);
  *cache = 1;
  __talos_eval_promotion_invalidate_range_v1(4, 4);
  assert(*cache == 1); // the hole between the two required ranges
}
