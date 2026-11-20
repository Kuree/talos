//===- ContextCacheTest.cpp - Caches live as long as their context --------===//
//
// Analysis caches keyed by operation and uniqued-attribute addresses must not
// outlive their context: a later context can reuse every one of those
// addresses, as the splits of talos-opt --split-input-file do on macOS. Each
// context with the Simulation dialect owns its caches and destroys them with
// itself.
//
//===----------------------------------------------------------------------===//

#include "talos/Dialect/Simulation/SimulationContextCache.h"
#include "talos/Dialect/Simulation/SimulationDialect.h"

#include "mlir/IR/MLIRContext.h"

#include "gtest/gtest.h"

#include <memory>

using namespace mlir;
using talos::sim::getContextCache;

namespace {

struct Cache {
  int value = 0;
};
struct OtherCache {
  int value = 0;
};

TEST(ContextCacheTest, OneCachePerContextAndType) {
  MLIRContext first, second;
  first.loadDialect<talos::sim::TalosSimulationDialect>();
  second.loadDialect<talos::sim::TalosSimulationDialect>();
  std::shared_ptr<Cache> cache = getContextCache<Cache>(&first);
  cache->value = 1;
  EXPECT_EQ(getContextCache<Cache>(&first), cache);
  EXPECT_EQ(getContextCache<Cache>(&second)->value, 0);
  EXPECT_NE(static_cast<void *>(getContextCache<OtherCache>(&first).get()),
            static_cast<void *>(cache.get()));
}

TEST(ContextCacheTest, DestroyedWithItsContext) {
  std::weak_ptr<Cache> cache;
  {
    MLIRContext context;
    context.loadDialect<talos::sim::TalosSimulationDialect>();
    cache = getContextCache<Cache>(&context);
    EXPECT_FALSE(cache.expired());
  }
  EXPECT_TRUE(cache.expired());
}

TEST(ContextCacheTest, NothingCachedWithoutTheDialect) {
  MLIRContext context;
  EXPECT_NE(getContextCache<Cache>(&context), getContextCache<Cache>(&context));
}

} // namespace
