#ifndef TALOS_UPF_SUPPLYEXPRESSION_H
#define TALOS_UPF_SUPPLYEXPRESSION_H
#include "SupplyNetwork.h"
#include "talos/Dialect/UPF/UPFAttrs.h"
#include "llvm/ADT/SmallVector.h"
#include <optional>
#include <set>
namespace talos {
struct SupplyReference {
  SupplyObject object;
  std::string function;
  std::set<std::string> required;
};
struct SupplyToken {
  upf::SupplyExpressionOpcode opcode;
  std::optional<SupplyReference> reference;
  int32_t value = 0;
  double real = 0;
};
struct SupplyExpression {
  llvm::SmallVector<SupplyToken> tokens;
  std::set<std::string> required;
};
mlir::FailureOr<SupplyExpression> parseSupplyExpression(
    llvm::StringRef text,
    llvm::function_ref<mlir::FailureOr<SupplyReference>(llvm::StringRef)>
        resolve,
    llvm::function_ref<void(const llvm::Twine &)> report);
bool refinesSupplyExpression(
    const SupplyExpression &previous, const SupplyExpression &next,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same);
// Bounded contradiction detection for Boolean branches and literal bounds.
// False means no supported contradiction was proved, not satisfiability;
// this does not solve cross-reference relations or the integer voltage grid.
// A missing answer means the 256-branch/65536-work limit was exceeded.
std::optional<bool> contradictsSupplyExpression(
    const SupplyExpression &expression,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same);
} // namespace talos
#endif
