#ifndef TALOS_UPF_RETENTIONREADBACK_H
#define TALOS_UPF_RETENTIONREADBACK_H

#include "ControlValue.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseSet.h"

namespace talos::upf_detail {
// An own-state read can use hidden normal storage while other callers must
// read the powered output. Until those callees are specialized per caller,
// inspect every statically bound body and reject readbacks or opaque dispatch.
inline mlir::LogicalResult
validateRetentionReadbackHelpers(sim::SimFuncOp function, uint64_t id,
                                 llvm::StringRef description) {
  llvm::SmallVector<mlir::Operation *> calls;
  mlir::Operation *opaque = nullptr;
  auto collect = [&](sim::SimFuncOp body) {
    body.walk([&](mlir::Operation *op) {
      if (mlir::isa<sim::SimCallOp, sim::SimClassDirectCallOp>(op))
        calls.push_back(op);
      else if (mlir::isa<sim::SimClassVirtualCallOp,
                         sim::SimClassVirtualTaskCallOp>(op))
        opaque = op;
    });
  };
  collect(function);
  llvm::DenseSet<mlir::Operation *> seen;
  while (!calls.empty() && !opaque) {
    auto *call = calls.pop_back_val();
    auto target = call->getAttrOfType<mlir::FlatSymbolRefAttr>("callee");
    auto helper = mlir::SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
        call, target);
    if (!helper || !seen.insert(helper).second)
      continue;
    bool readsState = false;
    helper.walk([&](sim::SimRefLoadOp load) {
      readsState |= storageID(load.getReference(), helper) == id;
    });
    if (readsState)
      return call->emitError()
             << description << " through helpers is not implemented";
    collect(helper);
  }
  if (opaque)
    return opaque->emitError()
           << description << " through virtual calls is not implemented";
  return mlir::success();
}
} // namespace talos::upf_detail
#endif
