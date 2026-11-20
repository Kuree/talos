//===- SimulationPrivateQueues.h - Native access to owned queues ---------===//

#ifndef TALOS_CONVERSION_SIMULATIONPRIVATEQUEUES_H
#define TALOS_CONVERSION_SIMULATIONPRIVATEQUEUES_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"
#include <cstdint>

namespace mlir::LLVM {
class LLVMFuncOp;
}
namespace talos::sim {
class SimDesignOp;
}

namespace talos::detail {

struct PrivateQueueUses {
  llvm::SmallVector<mlir::Operation *> propertyLoads;
  llvm::SmallVector<mlir::Operation *> accesses;
  unsigned apply() const;
};

bool hasNativeQueueLayout(mlir::ModuleOp module);
bool isPlainUnboundedQueue(mlir::Type type);
PrivateQueueUses analyzePrivateQueue(llvm::ArrayRef<mlir::Value> references,
                                     bool staticSlot = false);
unsigned specializeSingleProcessQueues(sim::SimDesignOp design);

enum class PrivateQueueAction { Size, Read, Append, Pop };
mlir::LLVM::LLVMFuncOp getPrivateQueueAccess(mlir::ModuleOp module,
                                             mlir::Location location,
                                             PrivateQueueAction action,
                                             uint64_t bytes = 0,
                                             bool four = false);

} // namespace talos::detail

#endif // TALOS_CONVERSION_SIMULATIONPRIVATEQUEUES_H
