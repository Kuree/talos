#ifndef TALOS_DIALECT_UPF_OPS_H
#define TALOS_DIALECT_UPF_OPS_H
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Dialect/UPF/UPFAttrs.h"
#include "talos/Dialect/UPF/UPFDialect.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include <algorithm>
namespace talos::upf {
inline bool isWithinPath(llvm::StringRef path, llvm::StringRef prefix) {
  return path == prefix || (path.starts_with(prefix) &&
                            path.drop_front(prefix.size()).starts_with('.'));
}
// Visit an ancestor and its entire subtree before similarly prefixed siblings
// such as `a$alias`. Ordinary byte ordering puts that sibling before `a.child`.
struct InstancePathLess {
  bool operator()(llvm::StringRef lhs, llvm::StringRef rhs) const {
    size_t common = 0, limit = std::min(lhs.size(), rhs.size());
    while (common < limit && lhs[common] == rhs[common])
      ++common;
    if (common == limit)
      return lhs.size() < rhs.size();
    if (lhs[common] == '.' || rhs[common] == '.')
      return lhs[common] == '.';
    return static_cast<unsigned char>(lhs[common]) <
           static_cast<unsigned char>(rhs[common]);
  }
};
inline llvm::ArrayRef<llvm::StringRef> getSupplyFunctionNames() {
  static constexpr llvm::StringRef names[] = {
      "power", "ground", "nwell", "pwell", "deepnwell", "deeppwell"};
  return names;
}
// Literal empty selections and references solely to structurally empty lists
// must not activate retention machinery before physical-state inference.
bool isStaticallyEmptyRetention(RetentionAttr strategy, mlir::Operation *from,
                                mlir::SymbolTableCollection *symbols = nullptr);
bool isDesignAttributeModelOnly(llvm::StringRef name);
bool isPortAttributeName(llvm::StringRef name);
bool isValidDesignAttributeValue(llvm::StringRef name, mlir::Attribute value);
bool isValidPortAttributeValue(llvm::StringRef name, mlir::Attribute value);
} // namespace talos::upf
#define GET_OP_CLASSES
#include "talos/Dialect/UPF/UPFOps.h.inc"
#endif
