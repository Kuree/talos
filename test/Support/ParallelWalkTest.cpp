//===- ParallelWalkTest.cpp - Concurrent symbol-use scans -----------------===//
//
// The concurrent scan of a large region reports the uses mlir::SymbolTable does,
// in the same order, including attributes of direct children and nested
// operations. A concurrent inventory from a module visits a nested symbol table
// as Operation::walk does.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/ParallelWalk.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Parser/Parser.h"

#include "gtest/gtest.h"

#include <atomic>
#include <string>
#include <type_traits>
#include <vector>

using namespace mlir;

namespace {

TEST(ParallelWalkTest, SymbolUsesMatchUpstreamOrder) {
  MLIRContext context;
  context.loadDialect<func::FuncDialect>();
  std::string body = "module {\n";
  unsigned count = 2 * talos::analysis::kParallelWalkMinChildren;
  for (unsigned index = 0; index != count; ++index) {
    std::string id = std::to_string(index);
    std::string next = std::to_string((index + 1) % count);
    body += "  func.func private @f" + id + "() attributes {own = @f" + next +
            ", list = [@f" + id + ", @f0]} {\n";
    if (index % 3)
      body += "    func.call @f" + next + "() : () -> ()\n";
    body += "    func.call @f0() {note = @f" + next + "} : () -> ()\n";
    body += "    return\n  }\n";
  }
  body += "}\n";
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(body, &context);
  ASSERT_TRUE(module);
  ASSERT_TRUE(talos::analysis::walksConcurrently(
      module->getOperation(), module->getBody()->getOperations().size()));
  Region *region = &module->getBodyRegion();
  auto expected = SymbolTable::getSymbolUses(region);
  auto actual = talos::analysis::getSymbolUsesConcurrently(region);
  ASSERT_TRUE(expected && actual);
  auto left = expected->begin(), right = actual->begin();
  size_t uses = 0;
  for (; left != expected->end() && right != actual->end();
       ++left, ++right, ++uses) {
    EXPECT_EQ(left->getUser(), right->getUser()) << "use " << uses;
    EXPECT_EQ(left->getSymbolRef(), right->getSymbolRef()) << "use " << uses;
  }
  EXPECT_TRUE(left == expected->end() && right == actual->end());
  EXPECT_GT(uses, count);
}

TEST(ParallelWalkTest, InventoryFansOutThroughLoneSymbolTableInWalkOrder) {
  MLIRContext context;
  context.loadDialect<func::FuncDialect>();
  std::string body = "module {\n  module @design {\n";
  unsigned count = 2 * talos::analysis::kParallelWalkMinChildren;
  for (unsigned index = 0; index != count; ++index) {
    std::string id = std::to_string(index);
    body += "    func.func private @f" + id +
            "() {\n      func.call @f" + id +
            "() : () -> ()\n      return\n    }\n";
  }
  body += "  }\n  func.func private @outer() {\n    return\n  }\n}\n";
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(body, &context);
  ASSERT_TRUE(module);
  Operation *root = module->getOperation();

  auto expectOrder = [&](auto order) {
    constexpr WalkOrder Order = decltype(order)::value;
    auto items = talos::analysis::planConcurrentWalk<Order>(root);
    // The design's children, the design itself and @outer.
    EXPECT_EQ(items.size(), count + 2);
    EXPECT_TRUE(talos::analysis::walksConcurrently(root, items.size()));
    std::vector<Operation *> expected;
    root->walk<Order>([&](Operation *op) { expected.push_back(op); });
    std::atomic<unsigned> visits = 0;
    auto actual = talos::analysis::collectInWalkOrder<Operation *, Order>(
        root, [&](Operation *) {
          ++visits;
          return true;
        });
    EXPECT_EQ(visits, expected.size());
    EXPECT_EQ(std::vector<Operation *>(actual.begin(), actual.end()), expected);
  };
  expectOrder(std::integral_constant<WalkOrder, WalkOrder::PreOrder>{});
  expectOrder(std::integral_constant<WalkOrder, WalkOrder::PostOrder>{});

  // The design itself is a unit of its own, not only its subtree.
  auto isDesign = [](ModuleOp nested) {
    return nested.getSymName() == "design";
  };
  EXPECT_TRUE(talos::analysis::anyNested<ModuleOp>(root, isDesign));
  EXPECT_FALSE(talos::analysis::anyNested<func::CallOp>(
      root, [](func::CallOp call) { return call.getCallee() == "missing"; }));
}

} // namespace
