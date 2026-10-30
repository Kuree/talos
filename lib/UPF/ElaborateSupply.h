#ifndef TALOS_UPF_ELABORATESUPPLY_H
#define TALOS_UPF_ELABORATESUPPLY_H
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/ArrayRef.h"
namespace talos {
struct SupplyTableEntry {
  mlir::StringAttr name;
  uint64_t storage;
  bool writable;
};
mlir::LogicalResult
lowerSupplyControls(sim::SimDesignOp design,
                    llvm::ArrayRef<SupplyTableEntry> entries);
} // namespace talos
#endif
