#ifndef TALOS_UPF_BALLOONRETENTION_H
#define TALOS_UPF_BALLOONRETENTION_H

#include "Retention.h"

namespace talos {
struct BalloonRegister {
  sim::SimStorageDeclOp declaration;
  llvm::SmallVector<mlir::Operation *> writers;
};

// IEEE 1801-2018 6.50/9.7.3: separate normal, retained and output state.
// Transfers use compiler-generated pure samplers and existing snapshot ops.
mlir::LogicalResult lowerBalloonRetention(
    const RetentionLoweringOptions &options, upf::RetentionAttr strategy,
    llvm::ArrayRef<upf::UPFSupplySetOp> primary,
    llvm::ArrayRef<upf::UPFSupplySetOp> retention,
    llvm::ArrayRef<BalloonRegister> registers, mlir::Operation *rootBoundary);
} // namespace talos
#endif
