#ifndef TALOS_DIALECT_NAMEDPROCESS_H
#define TALOS_DIALECT_NAMEDPROCESS_H

#include "mlir/IR/Operation.h"
#include "talos/Dialect/SemanticTraits.h"
#include "llvm/ADT/STLExtras.h"

namespace talos {
// IEEE 1800-2023 9.2/9.3.5: the outer named body (including an implicit
// labeled-statement block) supplies the supported whole-procedure name.
// Peel one leading timing wrapper, not nested conditional/loop/block scopes.
// Slang and SV keep the same body-symbol/path contract across conversion.
template <typename TimedStatement, typename BlockStatement>
BlockStatement getNamedProcessBody(mlir::Operation *procedure) {
  if (procedure->getNumRegions() != 1 || procedure->getRegion(0).empty() ||
      !llvm::hasSingleElement(procedure->getRegion(0).front()))
    return {};
  mlir::Operation *body = &procedure->getRegion(0).front().front();
  if (auto timed = mlir::dyn_cast<TimedStatement>(body)) {
    if (timed.getBody().empty())
      return {};
    body = nullptr;
    for (mlir::Operation &child : timed.getBody().front()) {
      if (child.hasTrait<mlir::OpTrait::SemanticTimingNode>())
        continue;
      if (body)
        return {};
      body = &child;
    }
  }
  auto block = mlir::dyn_cast_or_null<BlockStatement>(body);
  return block && block.getBlockSymbolAttr() && block.getBlockPathAttr() &&
                 !block.getBlockPathAttr().getValue().empty()
             ? block
             : BlockStatement{};
}
} // namespace talos
#endif
