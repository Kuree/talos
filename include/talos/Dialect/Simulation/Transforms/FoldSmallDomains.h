//===- FoldSmallDomains.h - Local condition proofs ---------------*- C++ -*-===//
#ifndef TALOS_DIALECT_SIMULATION_TRANSFORMS_FOLDSMALLDOMAINS_H
#define TALOS_DIALECT_SIMULATION_TRANSFORMS_FOLDSMALLDOMAINS_H

#include "mlir/IR/Value.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace talos::sim {
class SimFuncOp;
}

namespace talos {
/// Fold only bounded symbolic match-count conditions, using a revision-local
/// certificate that a queried SSA value may contain X but never Z. All decisions
/// precede mutation of this function. No-match/completeness checks are separate.
unsigned foldDisjointMatchCounts(
    sim::SimFuncOp function,
    llvm::function_ref<bool(mlir::Value)> isNeverZ);
} // namespace talos

#endif
