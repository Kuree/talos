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
SupplyStateEvaluation evaluateSupplySet(
    upf::UPFSupplySetOp set, mlir::OpBuilder &builder, mlir::Location location,
    llvm::function_ref<mlir::Value(mlir::FlatSymbolRefAttr)> read);
} // namespace talos
#endif
