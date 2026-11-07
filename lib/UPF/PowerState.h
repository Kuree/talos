#ifndef TALOS_UPF_POWERSTATE_H
#define TALOS_UPF_POWERSTATE_H
#include "mlir/IR/Builders.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/STLFunctionalExtras.h"
namespace talos {
struct SupplyStateEvaluation {
  mlir::Value normal, conflict, illegal;
};
// IEEE 1801-2018 6.47: interpretation for power-state evaluation only.
// Preserve packed storage/voltage and return the interpreted i32 state field.
mlir::Value
interpretedSupplyState(mlir::OpBuilder &builder, mlir::Location location,
                       mlir::Value packed,
                       std::optional<upf::PartialOnTranslation> translation);
llvm::SmallVector<mlir::FlatSymbolRefAttr>
getSupplySetReferences(upf::UPFSupplySetOp set);
// Strategy-local catalogs and supplying/global catalogs participate in the
// effective policy; another consumer strategy's private catalog does not.
llvm::SmallVector<upf::UPFSupplySetOp>
getRetentionSupplyPolicies(mlir::Operation *from, mlir::FlatSymbolRefAttr root,
                           mlir::SymbolTableCollection *symbols = nullptr,
                           llvm::function_ref<bool()> charge = {});
SupplyStateEvaluation evaluateSupplySet(
    upf::UPFSupplySetOp set, mlir::OpBuilder &builder, mlir::Location location,
    llvm::function_ref<mlir::Value(mlir::FlatSymbolRefAttr)> read);
} // namespace talos
#endif
