//===- VPIValueChangePoolTest.cpp - Change registration lifetime tests
//-----===//
#include "../lib/VPIValueChangePool.h"
#include "gtest/gtest.h"
#include <memory>
#include <vector>

namespace talos::runtime {
struct VPIValueChangePoolTestPeer {
  template <typename T>
  static uint64_t exhaustGeneration(VPIValueChangePool<T> &pool, uint64_t id) {
    const uint32_t index = static_cast<uint32_t>(id) - 1;
    pool.slot(index).generation = UINT32_MAX;
    return pool.handle(index, UINT32_MAX);
  }
  template <typename T>
  static void exhaustSequence(VPIValueChangePool<T> &pool) {
    pool.nextSequence = UINT64_MAX;
  }
  template <typename T>
  static void exhaustCapacity(VPIValueChangePool<T> &pool) {
    ASSERT_TRUE(pool.chunks.empty());
    pool.capacity = UINT32_MAX;
  }
};
} // namespace talos::runtime

namespace {
using talos::runtime::VPIValueChangePool;
using talos::runtime::VPIValueChangePoolTestPeer;

TEST(VPIValueChangePool, PublicationRevisionLimitsRegistrationOrderPerAlias) {
  VPIValueChangePool<unsigned> pool;
  const auto first = pool.add(7, 1);
  pool.add(9, 99);
  pool.add(7, 2);
  const auto published = pool.revision();
  pool.add(7, 3);
  std::vector<unsigned> values;
  pool.visit(7, published,
             [&](uint64_t, unsigned value) { values.push_back(value); });
  EXPECT_EQ(values, (std::vector<unsigned>{1, 2}));
  EXPECT_TRUE(pool.watches(7));
  EXPECT_TRUE(pool.watches(9));
  EXPECT_FALSE(pool.watches(0));
  EXPECT_EQ(pool.size(), 4u);
  ASSERT_NE(pool.find(first), nullptr);
  EXPECT_EQ(*pool.find(first), 1u);
}

TEST(VPIValueChangePool, RemovedAndReplacedCallbacksDoNotReceiveQueuedChanges) {
  VPIValueChangePool<unsigned> pool;
  auto old = pool.add(0, 1);
  const auto published = pool.revision();
  ASSERT_TRUE(pool.remove(old));
  auto replacement = pool.add(0, 2);
  EXPECT_NE(old, replacement);
  EXPECT_EQ(pool.find(old), nullptr);
  EXPECT_FALSE(pool.remove(old));
  unsigned calls = 0;
  pool.visit(0, published, [&](uint64_t, unsigned) { ++calls; });
  EXPECT_EQ(calls, 0u);
  pool.visit(0, pool.revision(), [&](uint64_t id, unsigned value) {
    EXPECT_EQ(id, replacement);
    EXPECT_EQ(value, 2u);
    ++calls;
  });
  EXPECT_EQ(calls, 1u);
  EXPECT_EQ(pool.find(0), nullptr);
  EXPECT_EQ(pool.find(UINT64_MAX), nullptr);
  EXPECT_FALSE(pool.remove(UINT64_C(1)));
}

struct Payload {
  unsigned number;
  std::unique_ptr<unsigned> value;
  explicit Payload(unsigned n)
      : number(n), value(std::make_unique<unsigned>(n)) {}
  Payload(Payload &&) = default;
};

TEST(VPIValueChangePool, SelfRemovalAndGrowthKeepPayloadAndTraversalStable) {
  VPIValueChangePool<Payload> pool;
  auto first = pool.add(7, Payload(1));
  auto next = pool.add(7, Payload(2));
  pool.add(7, Payload(3));
  std::vector<unsigned> seen;
  pool.visit(7, pool.revision(), [&](uint64_t id, const Payload &payload) {
    seen.push_back(payload.number);
    if (id != first)
      return;
    EXPECT_TRUE(pool.remove(first));
    EXPECT_TRUE(pool.remove(next));
    for (unsigned n = 4; n != 200; ++n)
      ASSERT_NE(pool.add(7, Payload(n)), 0u);
    // Growth crosses several pool chunks while the current record is pinned.
    EXPECT_EQ(payload.number, 1u);
    EXPECT_EQ(*payload.value, 1u);
  });
  EXPECT_EQ(seen, (std::vector<unsigned>{1, 3}));
  EXPECT_EQ(pool.find(first), nullptr);
  EXPECT_EQ(pool.find(next), nullptr);
  EXPECT_EQ(pool.size(), 197u);
}

TEST(VPIValueChangePool, NestedVisitsCanRemoveEveryRemainingRegistration) {
  VPIValueChangePool<Payload> pool;
  auto first = pool.add(7, Payload(1));
  pool.add(7, Payload(2));
  pool.add(7, Payload(3));
  std::vector<unsigned> outer, inner;
  pool.visit(7, pool.revision(), [&](uint64_t id, const Payload &payload) {
    outer.push_back(payload.number);
    EXPECT_EQ(id, first);
    EXPECT_TRUE(pool.remove(id));
    pool.add(7, Payload(4));
    pool.visit(7, pool.revision(), [&](uint64_t id, const Payload &nested) {
      inner.push_back(nested.number);
      EXPECT_TRUE(pool.remove(id));
      EXPECT_EQ(*nested.value, nested.number);
    });
    EXPECT_EQ(*payload.value, 1u);
  });
  EXPECT_EQ(outer, (std::vector<unsigned>{1}));
  EXPECT_EQ(inner, (std::vector<unsigned>{2, 3, 4}));
  EXPECT_EQ(pool.size(), 0u);
  EXPECT_FALSE(pool.watches(7));
  EXPECT_NE(pool.add(7, Payload(5)), first);
}

#if defined(__cpp_exceptions) || defined(_CPPUNWIND)
TEST(VPIValueChangePool, ExceptionUnwindingReleasesDeferredRecords) {
  VPIValueChangePool<Payload> pool;
  auto first = pool.add(7, Payload(1));
  EXPECT_THROW(pool.visit(7, pool.revision(),
                          [&](uint64_t id, const Payload &payload) {
                            EXPECT_TRUE(pool.remove(id));
                            EXPECT_EQ(*payload.value, 1u);
                            throw 7;
                          }),
               int);
  EXPECT_EQ(pool.size(), 0u);
  EXPECT_EQ(pool.find(first), nullptr);
  auto replacement = pool.add(7, Payload(2));
  EXPECT_NE(first, replacement);
  EXPECT_EQ(pool.allocatedSlots(), 64u);
}
#endif

TEST(VPIValueChangePool, ExhaustedGenerationRetiresSlotWithoutHandleReuse) {
  VPIValueChangePool<unsigned> pool;
  const auto original = pool.add(7, 1);
  const auto last =
      VPIValueChangePoolTestPeer::exhaustGeneration(pool, original);
  EXPECT_EQ(pool.find(original), nullptr);
  ASSERT_TRUE(pool.remove(last));
  auto replacement = pool.add(7, 2);
  EXPECT_NE(static_cast<uint32_t>(last), static_cast<uint32_t>(replacement));
  EXPECT_EQ(pool.find(last), nullptr);
  EXPECT_FALSE(pool.remove(last));
}

TEST(VPIValueChangePool, ExhaustedOrderRejectsRegistrationWithoutWrapping) {
  VPIValueChangePool<unsigned> pool;
  pool.add(7, 1);
  VPIValueChangePoolTestPeer::exhaustSequence(pool);
  auto last = pool.add(7, 2);
  ASSERT_NE(last, 0u);
  EXPECT_EQ(pool.revision(), UINT64_MAX);
  EXPECT_EQ(pool.add(9, 3), 0u);
  EXPECT_EQ(pool.size(), 2u);
  EXPECT_FALSE(pool.watches(9));
  std::vector<unsigned> seen;
  pool.visit(7, pool.revision(),
             [&](uint64_t, unsigned value) { seen.push_back(value); });
  EXPECT_EQ(seen, (std::vector<unsigned>{1, 2}));
  EXPECT_TRUE(pool.remove(last));
  EXPECT_EQ(pool.add(7, 4), 0u);
}

TEST(VPIValueChangePool, ExhaustedCapacityDoesNotPublishPartialRegistration) {
  VPIValueChangePool<unsigned> pool;
  VPIValueChangePoolTestPeer::exhaustCapacity(pool);
  EXPECT_EQ(pool.add(7, 1), 0u);
  EXPECT_EQ(pool.size(), 0u);
  EXPECT_EQ(pool.revision(), 0u);
  EXPECT_EQ(pool.cachedAliases(), 0u);
  EXPECT_FALSE(pool.watches(7));
}

TEST(VPIValueChangePool, RepeatedRegistrationBoundsSlotAndEmptyAliasStorage) {
  VPIValueChangePool<unsigned> pool;
  uint64_t previous = 0;
  for (unsigned n = 0; n != 100000; ++n) {
    auto next = pool.add(7, n);
    ASSERT_NE(next, 0u);
    EXPECT_NE(next, previous);
    EXPECT_EQ(pool.find(previous), nullptr);
    ASSERT_TRUE(pool.remove(next));
    previous = next;
  }
  EXPECT_EQ(pool.allocatedSlots(), 64u);
  EXPECT_EQ(pool.cachedAliases(), 1u);
  for (uint64_t key = 0; key != 4000; ++key) {
    auto id = pool.add(key, 0);
    ASSERT_NE(id, 0u);
    ASSERT_TRUE(pool.remove(id));
    EXPECT_LE(pool.cachedAliases(), 256u);
  }
  EXPECT_EQ(pool.allocatedSlots(), 64u);
  EXPECT_EQ(pool.cachedAliases(), 256u);
  EXPECT_EQ(pool.size(), 0u);
}
} // namespace
