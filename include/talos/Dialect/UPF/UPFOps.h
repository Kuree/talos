#ifndef TALOS_DIALECT_UPF_OPS_H
#define TALOS_DIALECT_UPF_OPS_H
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/SymbolTable.h"
#include "talos/Dialect/UPF/UPFAttrs.h"
#include "talos/Dialect/UPF/UPFDialect.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
namespace talos::upf {
inline llvm::ArrayRef<llvm::StringRef> getSupplyFunctionNames() {
  static constexpr llvm::StringRef names[] = {
      "power", "ground", "nwell", "pwell", "deepnwell", "deeppwell"};
  return names;
}
} // namespace talos::upf
#define GET_OP_CLASSES
#include "talos/Dialect/UPF/UPFOps.h.inc"
#endif
