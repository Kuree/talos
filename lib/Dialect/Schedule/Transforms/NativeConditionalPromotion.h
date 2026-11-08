//===- NativeConditionalPromotion.h - Conditional input proofs -*- C++ -*-===//
#ifndef TALOS_SCHEDULE_NATIVECONDITIONALPROMOTION_H
#define TALOS_SCHEDULE_NATIVECONDITIONALPROMOTION_H

#include "mlir/IR/SymbolTable.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

namespace talos::detail {
struct NativeStateLayout;

/// Optional, read-only entry predicate for conditionally unused certificate
/// ranges. Returns null without changing the source when no proof is available.
sim::SimFuncOp materializeConditionalPromotionProbe(
    sim::SimFuncOp source, const NativeStateLayout &layout,
    const analysis::HandleDataflowAnalysis &handles, mlir::SymbolTable &symbols,
    llvm::StringRef name, uint64_t codeUnit);
} // namespace talos::detail
#endif // TALOS_SCHEDULE_NATIVECONDITIONALPROMOTION_H
