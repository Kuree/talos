#ifndef TALOS_DIALECT_UPF_ATTRS_H
#define TALOS_DIALECT_UPF_ATTRS_H
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/UPF/UPFEnums.h.inc"
#include <optional>
#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/UPF/UPFAttrs.h.inc"
namespace talos::upf {
inline constexpr llvm::StringLiteral partialOnTranslationName =
    "upf.partial_on_translation";
// An absent setting preserves PARTIAL_ON; OFF/FULL_ON are global
// interpretations.
std::optional<PartialOnTranslation>
getPartialOnTranslation(mlir::Operation *operation);
} // namespace talos::upf
#endif
