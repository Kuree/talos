//===- NativeRankSolver.h - Native eval ranking -*- C++ -*-===//
#ifndef TALOS_SOLVER_NATIVERANKSOLVER_H
#define TALOS_SOLVER_NATIVERANKSOLVER_H
#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/Error.h"
#include <cstdint>
#include <utility>
#include <vector>
namespace talos::solver {
struct RankSlot {
  bool repeatable, twoState, convergence;
  bool hasFixedBackwardWake;
  unsigned helper;
};
using RankEdge = std::pair<uint32_t, uint32_t>;
using RankCost = std::pair<unsigned, unsigned>;
RankCost backwardWakeCost(llvm::ArrayRef<RankEdge> edges,
                          llvm::ArrayRef<uint32_t> positions,
                          llvm::ArrayRef<uint8_t> fixed = {});
/// Optimize one SCC/island interval of compatible native slots. On budget
/// exhaustion the result is a verified incumbent, and the proof flag is false.
llvm::Expected<bool> minimizeRankPermutation(
    llvm::ArrayRef<RankSlot> slots, llvm::ArrayRef<RankEdge> edges,
    llvm::ArrayRef<std::vector<uint32_t>> chains, std::vector<uint32_t> &order);
bool nativeRankSolverAvailable();
} // namespace talos::solver
#endif
