//===- NativeRankPlanning.h - Native eval ranking -*- C++ -*-===//
#ifndef TALOS_CONVERSION_NATIVE_RANK_PLANNING_H
#define TALOS_CONVERSION_NATIVE_RANK_PLANNING_H
#include "../SimulationToSchedule/NativeRankTrial.h"
#include "llvm/Support/CommandLine.h"
#include <memory>

namespace mlir {
class OpPassManager;
class Pass;
} // namespace mlir
namespace talos::detail {
inline auto nativeRankStrategyValues() {
  using analysis::NativeRankStrategy;
  return llvm::cl::values(clEnumValN(NativeRankStrategy::Heuristic, "heuristic",
                                     "Dependency traversal"),
                          clEnumValN(NativeRankStrategy::Z3, "z3",
                                     "Constrained native evaluator ranking"));
}
void buildNativeProcesses(mlir::OpPassManager &, bool nativeWords,
                          bool nativeAggregates,
                          NativeRankTrial *trial = nullptr);

std::unique_ptr<mlir::Pass>
createRankNativeProcessesPass(analysis::NativeRankStrategy strategy,
                              bool nativeWords, bool nativeAggregates);
void registerNativeRankPlanningPass();
} // namespace talos::detail
#endif
