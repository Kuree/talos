//===- OrderedDenseAnalysis.h - Dense visits in CFG order ------*- C++ -*-===//
//
// DataFlowSolver's worklist is first-in, first-out, so updates reach a join one
// predecessor at a time and each arrival is propagated through everything
// downstream of it. In a large fused body these waves multiply: one kernel of
// 41K operations took 10M visits. The least fixpoint does not depend on the
// visit order, so an analysis can take its pending visits in reverse
// post-order instead: a join then normally sees all its forward predecessors at
// once, and a loop settles before anything after it runs.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_ANALYSIS_ORDEREDDENSEANALYSIS_H
#define TALOS_ANALYSIS_ORDEREDDENSEANALYSIS_H

#include "mlir/Analysis/DataFlow/DenseAnalysis.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/RegionGraphTraits.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/PostOrderIterator.h"

#include <cstdint>
#include <functional>
#include <queue>
#include <utility>
#include <vector>

namespace talos::analysis {

/// A dense forward analysis that holds its work items in a queue ordered by
/// reverse post-order. It takes the next item only once a whole round of the
/// solver's worklist has passed without a new one, so that control-flow
/// liveness and other analyses settle first. Below `minimumBlocks` blocks,
/// waves stay small and items pass straight through.
template <typename LatticeT>
class OrderedDenseForwardDataFlowAnalysis
    : public mlir::dataflow::DenseForwardDataFlowAnalysis<LatticeT> {
  using Base = mlir::dataflow::DenseForwardDataFlowAnalysis<LatticeT>;

public:
  explicit OrderedDenseForwardDataFlowAnalysis(mlir::DataFlowSolver &solver)
      : Base(solver), solver(solver) {}

  mlir::LogicalResult initialize(mlir::Operation *top) override {
    number(top);
    if (blocks < minimumBlocks)
      ranks.clear();
    else
      tick = this->getProgramPointBefore(&tickBlock);
    return Base::initialize(top);
  }

  mlir::LogicalResult visit(mlir::ProgramPoint *point) override {
    if (!tick)
      return Base::visit(point);
    if (point != tick) {
      if (queued.insert(point).second) {
        pending.emplace(rankOf(point), point);
        arrived = true;
      }
      schedule();
      return mlir::success();
    }
    scheduled = false;
    if (pending.empty())
      return mlir::success();
    if (arrived) {
      arrived = false;
      schedule();
      return mlir::success();
    }
    mlir::ProgramPoint *next = pending.top().second;
    pending.pop();
    queued.erase(next);
    if (!pending.empty())
      schedule();
    return Base::visit(next);
  }

private:
  static constexpr unsigned minimumBlocks = 32;
  using Item = std::pair<uint32_t, mlir::ProgramPoint *>;

  void number(mlir::Operation *op) {
    for (mlir::Region &region : op->getRegions()) {
      if (region.empty())
        continue;
      auto numberBlock = [&](mlir::Block *block) {
        if (!ranks.try_emplace(block, ranks.size()).second)
          return;
        ++blocks;
        for (mlir::Operation &nested : *block) {
          ranks.try_emplace(&nested, ranks.size());
          if (nested.getNumRegions())
            number(&nested);
        }
      };
      for (mlir::Block *block :
           llvm::ReversePostOrderTraversal<mlir::Block *>(&region.front()))
        numberBlock(block);
      for (mlir::Block &block : region)
        numberBlock(&block);
    }
  }
  uint32_t rankOf(mlir::ProgramPoint *point) const {
    return ranks.lookup(point->isBlockStart()
                            ? static_cast<const void *>(point->getBlock())
                            : point->getPrevOp());
  }
  void schedule() {
    if (!scheduled) {
      scheduled = true;
      solver.enqueue({tick, this});
    }
  }

  mlir::DataFlowSolver &solver;
  llvm::DenseMap<const void *, uint32_t> ranks;
  unsigned blocks = 0;
  /// Never in the IR: its entry is the program point of the solver's turns.
  mlir::Block tickBlock;
  mlir::ProgramPoint *tick = nullptr;
  std::priority_queue<Item, std::vector<Item>, std::greater<Item>> pending;
  llvm::DenseSet<mlir::ProgramPoint *> queued;
  bool scheduled = false, arrived = false;
};

} // namespace talos::analysis

#endif
