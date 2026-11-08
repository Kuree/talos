//===- VPIValueChangeQueueTest.cpp - Change publication ordering tests
//------===//
#include "../lib/VPIValueChangeQueue.h"
#include "gtest/gtest.h"
#include <stdexcept>
#include <tuple>
#include <vector>

namespace {
using talos::runtime::VPIPackedChangePublication;
using talos::runtime::VPIValueChangeQueue;

VPIPackedChangePublication change(uint64_t oldValue, uint64_t newValue,
                                  uint64_t alias = 7, uint64_t time = 11) {
  return {alias, oldValue, 0, newValue, 0, time, 64};
}

TEST(VPIValueChangeQueue,
     ApplicationReturnDefersEveryPutAndPreservesSnapshots) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  std::vector<std::tuple<unsigned, uint64_t, uint64_t>> seen;
  auto deliver = [&](uint64_t, unsigned number,
                     const VPIPackedChangePublication &event) {
    seen.emplace_back(number, event.newValue, event.time);
  };
  {
    VPIValueChangeQueue<unsigned>::ClientScope application(queue);
    ASSERT_TRUE(queue.publish(change(0, 1)));
    queue.drain(deliver);
    EXPECT_TRUE(seen.empty());
    {
      VPIValueChangeQueue<unsigned>::ClientScope nestedApplication(queue);
      ASSERT_TRUE(queue.publish(change(1, 2, 7, 12)));
    }
    queue.drain(deliver);
    EXPECT_TRUE(seen.empty());
  }
  // Returning from a VPI function or destroying a scope never invokes a
  // callback. Only the simulator's explicit application-return fence does.
  EXPECT_TRUE(seen.empty());
  ASSERT_EQ(queue.pendingCount(), 2u);
  queue.drain(deliver);
  EXPECT_EQ(seen, (decltype(seen){{1, 1, 11}, {1, 2, 12}}));
  EXPECT_EQ(queue.pendingCount(), 0u);
}

TEST(VPIValueChangeQueue, CallbackPutsRunAfterItsReturnWithoutRecursing) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  std::vector<unsigned> order;
  unsigned depth = 0;
  auto deliver = [&](uint64_t, unsigned,
                     const VPIPackedChangePublication &event) {
    EXPECT_EQ(depth++, 0u);
    order.push_back(static_cast<unsigned>(event.newValue * 10));
    if (event.newValue == 1) {
      ASSERT_TRUE(queue.publish(change(1, 2)));
      // A nested attempt to enter the main loop cannot deliver a callback
      // inside the application that issued the put.
      queue.drain([&](auto...) { ADD_FAILURE() << "reentrant delivery"; });
    }
    order.push_back(static_cast<unsigned>(event.newValue * 10 + 1));
    --depth;
  };
  ASSERT_TRUE(queue.publish(change(0, 1)));
  queue.drain(deliver);
  order.push_back(99); // The next design statement.
  EXPECT_EQ(order, (std::vector<unsigned>{10, 11, 20, 21, 99}));
}

TEST(VPIValueChangeQueue, RegistrationFrontierIsCapturedAtEachPublication) {
  VPIValueChangeQueue<unsigned> queue;
  auto first = queue.add(7, 1);
  ASSERT_TRUE(queue.publish(change(0, 1)));
  queue.add(7, 2);
  ASSERT_TRUE(queue.publish(change(1, 2)));
  std::vector<std::pair<unsigned, uint64_t>> seen;
  queue.drain(
      [&](uint64_t, unsigned number, const VPIPackedChangePublication &event) {
        seen.emplace_back(number, event.newValue);
      });
  EXPECT_EQ(seen, (decltype(seen){{1, 1}, {1, 2}, {2, 2}}));
  ASSERT_TRUE(queue.publish(change(2, 3)));
  ASSERT_TRUE(queue.remove(first));
  auto replacement = queue.add(7, 3);
  EXPECT_NE(first, replacement);
  seen.clear();
  queue.drain(
      [&](uint64_t, unsigned number, const VPIPackedChangePublication &event) {
        seen.emplace_back(number, event.newValue);
      });
  EXPECT_EQ(seen, (decltype(seen){{2, 3}}));
}

TEST(VPIValueChangeQueue, FourStateChangesAndSelectionsUseBothCoherentPlanes) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  auto event = change(0, 0);
  event.width = 4;
  ASSERT_TRUE(queue.publish(event));
  EXPECT_EQ(queue.pendingCount(), 0u);
  event.newUnknown = 8; // 0 -> X at bit 3.
  ASSERT_TRUE(queue.publish(event));
  event.oldUnknown = 8;
  event.newValue = 8; // X -> Z at bit 3.
  ASSERT_TRUE(queue.publish(event));
  event.oldValue = 8;
  event.newUnknown = 0; // Z -> 1 at bit 3.
  ASSERT_TRUE(queue.publish(event));
  event.oldUnknown = 0;
  event.newValue = 8 | (uint64_t{1} << 63); // Outside the declared root.
  ASSERT_TRUE(queue.publish(event));
  EXPECT_EQ(queue.pendingCount(), 3u);
  unsigned calls = 0;
  queue.drain(
      [&](uint64_t, unsigned, const VPIPackedChangePublication &published) {
        EXPECT_TRUE(published.changes(3, 1));
        EXPECT_FALSE(published.changes(0, 3));
        EXPECT_FALSE(published.changes(4, 1));
        EXPECT_FALSE(published.changes(0, 0));
        EXPECT_FALSE(published.changes(0, 5));
        EXPECT_EQ(published.newValue & ~uint64_t{15}, 0u);
        ++calls;
      });
  EXPECT_EQ(calls, 3u);
  auto wide = change(0, uint64_t{1} << 63);
  EXPECT_TRUE(wide.changes(0, 64));
  EXPECT_TRUE(wide.changes(63, 1));
  EXPECT_FALSE(wide.changes(64, 1));
  EXPECT_FALSE(wide.changes(UINT32_MAX, UINT32_MAX));
  wide.width = 65;
  EXPECT_FALSE(wide.changes(64, 1));
  EXPECT_FALSE(queue.publish(wide));
  wide.width = 0;
  EXPECT_FALSE(queue.publish(wide));
}

TEST(VPIValueChangeQueue, DeliverySurvivesRemovalAndPendingVectorGrowth) {
  VPIValueChangeQueue<unsigned> queue;
  const auto first = queue.add(7, 1);
  const auto removed = queue.add(7, 2);
  queue.add(9, 3);
  ASSERT_TRUE(queue.publish(change(0, 1)));
  std::vector<unsigned> seen;
  queue.drain([&](uint64_t id, unsigned &number,
                  const VPIPackedChangePublication &event) {
    seen.push_back(number);
    if (id != first)
      return;
    ASSERT_TRUE(queue.remove(first));
    ASSERT_TRUE(queue.remove(removed));
    for (unsigned n = 0; n != 1024; ++n) {
      ASSERT_NE(queue.add(10 + n, n), 0u);
      ASSERT_TRUE(queue.publish(change(n, n + 1, 9)));
    }
    // Both the current record and current publication stay valid across pool
    // chunk growth and pending-vector reallocation.
    EXPECT_EQ(number, 1u);
    EXPECT_EQ(event.newValue, 1u);
  });
  ASSERT_EQ(seen.size(), 1025u);
  EXPECT_EQ(seen.front(), 1u);
  for (size_t i = 1; i != seen.size(); ++i)
    EXPECT_EQ(seen[i], 3u);
  EXPECT_EQ(queue.pendingCount(), 0u);
  EXPECT_FALSE(queue.remove(first));
}

TEST(VPIValueChangeQueue, NativeStoreFenceRunsBeforeLaterDesignWork) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  unsigned laterStatement = 0;
  std::vector<uint64_t> seen;
  auto deliver = [&](uint64_t, unsigned,
                     const VPIPackedChangePublication &event) {
    EXPECT_EQ(laterStatement, 0u);
    seen.push_back(event.newValue);
  };
  ASSERT_TRUE(queue.publish(change(0, 1)));
  queue.drain(deliver);
  ASSERT_TRUE(queue.publish(change(1, 2)));
  queue.drain(deliver);
  laterStatement = 1;
  EXPECT_EQ(seen, (std::vector<uint64_t>{1, 2}));
}

TEST(VPIValueChangeQueue, LongCallbackPutChainUsesIterativeDelivery) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  ASSERT_TRUE(queue.publish(change(0, 1)));
  uint64_t calls = 0;
  queue.drain([&](uint64_t, unsigned, const VPIPackedChangePublication &event) {
    EXPECT_EQ(event.newValue, ++calls);
    if (calls != 100000)
      ASSERT_TRUE(queue.publish(change(calls, calls + 1)));
  });
  EXPECT_EQ(calls, 100000u);
  EXPECT_EQ(queue.pendingCount(), 0u);
}

#if defined(__cpp_exceptions)
TEST(VPIValueChangeQueue, ExceptionReleasesDeliveryAndApplicationGuards) {
  VPIValueChangeQueue<unsigned> queue;
  queue.add(7, 1);
  ASSERT_TRUE(queue.publish(change(0, 1)));
  ASSERT_TRUE(queue.publish(change(1, 2)));
  EXPECT_THROW(
      queue.drain([](auto...) { throw std::runtime_error("callback"); }),
      std::runtime_error);
  EXPECT_EQ(queue.pendingCount(), 1u);
  std::vector<uint64_t> seen;
  queue.drain([&](uint64_t, unsigned, const VPIPackedChangePublication &event) {
    seen.push_back(event.newValue);
  });
  EXPECT_EQ(seen, (std::vector<uint64_t>{2}));
  ASSERT_TRUE(queue.publish(change(2, 3)));
  queue.drain([&](auto...) { seen.push_back(3); });
  EXPECT_EQ(seen, (std::vector<uint64_t>{2, 3}));
}
#endif
} // namespace
