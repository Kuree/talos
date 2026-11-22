//===- StableHandleTest.cpp - Stable-handle offset identities -------------===//
//
// The compiler folds and lowers schedule.handle.offset by identities of
// talos_rt_stable_handle_offset: an offset by zero is its handle, one proved
// in bounds is the plain sum, and two proved offsets are one. These tests pin
// each identity on the domain the operation states (a handle as the runtime
// encodes it, or the invalid handle) and the counterexamples outside it that
// restrict the folds. An invalid handle names no storage: a read through it
// yields the invalid-index value and a write does nothing (IEEE 1800-2023
// 7.4.5, 11.5.1).
//
//===----------------------------------------------------------------------===//

#include "talos/Runtime/StableHandle.h"
#include "gtest/gtest.h"

#include <cstdint>
#include <limits>

namespace {
constexpr uint64_t invalid = UINT64_MAX;
constexpr int64_t int32Max = std::numeric_limits<int32_t>::max();
constexpr int64_t int32Min = std::numeric_limits<int32_t>::min();

uint64_t global(int64_t offset) {
  return talos_rt_stable_handle_encode(TALOS_RT_STABLE_HANDLE_GLOBAL, 0,
                                       offset);
}
uint64_t staticHandle(uint32_t id, int64_t offset) {
  return talos_rt_stable_handle_encode(TALOS_RT_STABLE_HANDLE_STATIC, id,
                                       offset);
}
uint64_t automatic(uint32_t id, int64_t offset) {
  return talos_rt_stable_handle_encode(TALOS_RT_STABLE_HANDLE_AUTOMATIC, id,
                                       offset);
}
uint64_t offset(uint64_t handle, int64_t amount) {
  return talos_rt_stable_handle_offset(handle, amount);
}

// offset(h, 0) == h for every handle the runtime encodes, at the ends of each
// kind's identifier and offset ranges, and for the invalid handle.
TEST(StableHandle, OffsetByZeroIsTheHandle) {
  const uint64_t handles[] = {
      global(0),
      global(int64_t(TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG) - 1),
      staticHandle(1, 0),
      staticHandle(1, -3),
      staticHandle(1, int32Max),
      staticHandle(1, int32Min),
      staticHandle(TALOS_RT_STABLE_HANDLE_MAX_STATIC_ID, 0),
      staticHandle(TALOS_RT_STABLE_HANDLE_MAX_STATIC_ID, -3),
      staticHandle(TALOS_RT_STABLE_HANDLE_MAX_STATIC_ID, int32Max),
      staticHandle(TALOS_RT_STABLE_HANDLE_MAX_STATIC_ID, int32Min),
      automatic(1, int32Min),
      automatic(TALOS_RT_STABLE_HANDLE_MAX_AUTOMATIC_ID, int32Max),
      invalid,
  };
  for (uint64_t handle : handles) {
    talos_rt_stable_handle_v1 decoded;
    ASSERT_EQ(talos_rt_stable_handle_decode(handle, &decoded),
              handle != invalid)
        << handle;
    EXPECT_EQ(offset(handle, 0), handle) << handle;
  }
}

// A word the runtime cannot decode is no handle: offsetting it by zero gives
// the invalid handle, not the word. The zero fold holds only on the domain
// the operation states.
TEST(StableHandle, OffsetByZeroOfANonHandleIsInvalid) {
  const uint64_t words[] = {
      // A dynamic event, not state.
      TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG,
      TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG | 5,
      // Static and automatic identifier 0, and an automatic identifier past
      // the largest.
      TALOS_RT_STABLE_HANDLE_STATIC_TAG | 5,
      TALOS_RT_STABLE_HANDLE_AUTOMATIC_TAG | 5,
      TALOS_RT_STABLE_HANDLE_AUTOMATIC_TAG |
          (uint64_t(TALOS_RT_STABLE_HANDLE_MAX_AUTOMATIC_ID) + 1) << 32,
  };
  for (uint64_t word : words)
    EXPECT_EQ(offset(word, 0), invalid) << word;
}

// With the old and new offsets in [0, INT32_MAX], the offset is the plain
// sum: the low word neither carries into nor borrows from the identifier.
TEST(StableHandle, InBoundsOffsetIsTheSum) {
  struct Case {
    uint64_t handle;
    int64_t amount;
  };
  const Case cases[] = {
      {staticHandle(3, 5), 4},
      {staticHandle(3, 5), -5},
      {staticHandle(3, 0), int32Max},
      {staticHandle(3, int32Max), -int32Max},
      {staticHandle(TALOS_RT_STABLE_HANDLE_MAX_STATIC_ID, 1), int32Max - 1},
      {automatic(2, 7), 1},
      {automatic(TALOS_RT_STABLE_HANDLE_MAX_AUTOMATIC_ID, 0), int32Max},
      {global(10), 5},
      {global(int32Max), -int32Max},
  };
  for (const Case &c : cases)
    EXPECT_EQ(offset(c.handle, c.amount), c.handle + uint64_t(c.amount))
        << c.handle << " + " << c.amount;
}

// The proof's two boundaries: a new offset past INT32_MAX is invalid, where
// the sum wraps to the object's lowest offset; a static or automatic one below
// 0 is valid, but the sum borrows from the identifier and names another
// object.
TEST(StableHandle, OffsetsOutOfBoundsAreNotTheSum) {
  uint64_t last = staticHandle(3, int32Max);
  EXPECT_EQ(offset(last, 1), invalid);
  EXPECT_EQ(last + 1, staticHandle(3, int32Min));

  uint64_t first = staticHandle(3, 0);
  EXPECT_EQ(offset(first, -1), staticHandle(3, -1));
  EXPECT_EQ(first - 1, staticHandle(2, -1));

  uint64_t frame = automatic(2, 0);
  EXPECT_EQ(offset(frame, -1), automatic(2, -1));
  EXPECT_EQ(frame - 1, automatic(1, -1));
}

// Each unproved offset checks its own result, so a chain is not the offset by
// its total: the first step leaves the static range and stays invalid. Only
// proved chains merge.
TEST(StableHandle, ChainsCheckEachStep) {
  uint64_t root = staticHandle(3, 0);
  int64_t past = int64_t(1) << 31;
  EXPECT_EQ(offset(offset(root, past), 5 - past), invalid);
  EXPECT_EQ(offset(root, 5), staticHandle(3, 5));

  // Proved steps compose: both stay in [0, INT32_MAX].
  EXPECT_EQ(offset(offset(root, 2), 3), offset(root, 5));
}

// Results a kind cannot represent are the invalid handle: a negative global
// offset, an offset that overflows int64, a static or automatic offset outside
// int32, and any offset of the invalid handle. A static or automatic offset
// may be negative: a part-select may start below its object (11.5.1).
TEST(StableHandle, UnrepresentableOffsetsAreInvalid) {
  EXPECT_EQ(offset(global(10), 5), global(15));
  EXPECT_EQ(offset(global(10), -11), invalid);
  EXPECT_EQ(offset(global(10), std::numeric_limits<int64_t>::max()), invalid);
  EXPECT_EQ(
      offset(global(0), int64_t(TALOS_RT_STABLE_HANDLE_DYNAMIC_EVENT_TAG)),
      invalid);
  EXPECT_EQ(offset(staticHandle(3, 5), -7), staticHandle(3, -2));
  EXPECT_EQ(offset(staticHandle(3, int32Min), -1), invalid);
  EXPECT_EQ(offset(automatic(2, 7), 1), automatic(2, 8));
  EXPECT_EQ(offset(automatic(2, int32Max), 1), invalid);
  EXPECT_EQ(offset(invalid, 1), invalid);
  EXPECT_EQ(offset(invalid, -1), invalid);
}
} // namespace
