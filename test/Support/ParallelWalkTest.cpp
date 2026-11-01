//===- ParallelWalkTest.cpp - Concurrent symbol-use scans -----------------===//
//
// The concurrent scan of a large region reports the uses mlir::SymbolTable does,
// in the same order, including attributes of direct children and nested
// operations.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/ParallelWalk.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Parser/Parser.h"

#include "gtest/gtest.h"

#include <string>

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

} // namespace
