//===- FoldSmallDomains.cpp - Decide two-state conditions exhaustively ----===//
//
// A branch or select condition computed from at most `maxDomainBits` bits of
// two-state values is evaluated for every value of those bits that the
// conditions of its dominating branch edges admit. A condition that takes one
// value on all of them is decided: the branch takes that edge and the select
// that operand.
//
// This is how a unique or priority case or if whose items cover every
// two-state value without overlap loses its violation check and its dead
// default (IEEE 1800-2023 12.4.2, 12.5.3): two-state values carry no X or Z,
// so no execution reaches the check and no violation report is due.
// Four-state values are never evaluated: X and Z can still select the
// default, or several casez items through z wildcards (12.5.1), and those
// reports must still be issued (12.4.2.1).
//
// Soundness of the edge constraints: an edge P->D, the only entry of a block
// D that dominates the use, was taken with the current values of its
// condition's inputs, because each input is defined in a block dominating P,
// and running that definition again leads back to the use only through the
// edge.
//
//===----------------------------------------------------------------------===//

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"
#include "talos/Dialect/Simulation/Transforms/TwoStateEvaluation.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_TALOSSIMFOLDSMALLDOMAINSPASS
#include "talos/Dialect/Simulation/Transforms/Passes.h.inc"

namespace {
using sim::TwoStateEvaluator;
using sim::TwoStateSlice;

/// The input domain: at most 2^16 values, as Verilator's case analysis.
constexpr unsigned maxDomainBits = 16;
/// Operations one evaluation may interpret.
constexpr unsigned maxSliceOps = 512;
/// Interpreted operations per condition, summed over its domain.
constexpr uint64_t maxConditionWork = uint64_t{1} << 22;
/// Interpreted operations per function.
constexpr uint64_t maxFunctionWork = uint64_t{1} << 26;
/// Dominating branch edges considered per condition.
constexpr unsigned maxEdges = 32;
/// Assignments tried before the exhaustive walk.
constexpr unsigned maxProbes = 256;

/// A branch edge that is the only entry of the block it enters.
struct Edge {
  Value condition;
  bool sense;
  SmallVector<Value> leaves;
};

class Decider {
public:
  explicit Decider(Operation *function) : dominance(function) {}

  /// The single value `condition` takes in `block` over every two-state value
  /// of its inputs that the dominating branch edges admit, if there is one.
  std::optional<bool> decide(Value condition, Block *block) {
    if (work > maxFunctionWork)
      return std::nullopt;
    FailureOr<TwoStateSlice> own =
        sim::buildTwoStateSlice(condition, maxDomainBits, maxSliceOps);
    if (failed(own))
      return std::nullopt;

    // Constraints connected to the condition's inputs, directly or through
    // other constraints: one on unrelated inputs is satisfiable whatever the
    // condition's inputs are, so it cannot change the decision. Dropping a
    // constraint only enlarges the evaluated set, so one that does not fit
    // the budgets is skipped.
    SmallVector<const Edge *> edges = dominatingEdges(block);
    llvm::SmallPtrSet<Value, 8> leaves(own->leaves.begin(), own->leaves.end());
    SmallVector<Value> roots{condition};
    SmallVector<const Edge *> constraints;
    TwoStateSlice slice = std::move(*own);
    for (bool grew = true; grew;) {
      grew = false;
      for (const Edge *&edge : edges) {
        if (!edge || llvm::none_of(edge->leaves, [&](Value leaf) {
              return leaves.contains(leaf);
            }))
          continue;
        roots.push_back(edge->condition);
        FailureOr<TwoStateSlice> combined =
            sim::buildTwoStateSlice(roots, maxDomainBits, maxSliceOps);
        if (failed(combined)) {
          roots.pop_back();
          edge = nullptr;
          continue;
        }
        slice = std::move(*combined);
        leaves.insert(edge->leaves.begin(), edge->leaves.end());
        constraints.push_back(edge);
        edge = nullptr;
        grew = true;
      }
    }
    uint64_t ops = std::max<size_t>(slice.ops.size(), 1);
    uint64_t assignments = uint64_t{1} << slice.width;
    if (assignments * ops > maxConditionWork)
      return std::nullopt;

    TwoStateEvaluator evaluator(slice);
    std::optional<bool> decided;
    // Evaluates one assignment; false once the condition took both values or
    // the evaluation failed.
    auto admit = [&](uint64_t assignment) {
      work += ops;
      if (failed(evaluator.run(assignment)))
        return false;
      if (llvm::any_of(constraints, [&](const Edge *edge) {
            return evaluator.get(edge->condition).getBoolValue() != edge->sense;
          }))
        return true;
      bool value = evaluator.get(condition).getBoolValue();
      if (decided && *decided != value)
        return false;
      decided = value;
      return true;
    };
    // Probes that usually expose both values early: each input at a constant
    // of the slice or one off it, all zeros and all ones.
    for (uint64_t probe : probes(slice))
      if (!admit(probe))
        return std::nullopt;
    for (uint64_t assignment = 0; assignment < assignments; ++assignment)
      if (!admit(assignment))
        return std::nullopt;
    return decided;
  }

private:
  /// The edges dominating `block`, nearest first; each is built once.
  SmallVector<const Edge *> dominatingEdges(Block *block) {
    SmallVector<const Edge *> result;
    // A single-block region has no dominator tree and no branch edges.
    if (block->getParent()->hasOneBlock())
      return result;
    for (DominanceInfoNode *node = dominance.getNode(block);
         node && result.size() < maxEdges; node = node->getIDom())
      if (const Edge *edge = edgeInto(node->getBlock()))
        result.push_back(edge);
    return result;
  }

  const Edge *edgeInto(Block *block) {
    if (!block)
      return nullptr;
    if (auto found = edgeCache.find(block); found != edgeCache.end())
      return found->second ? &*found->second : nullptr;
    std::optional<Edge> edge;
    Block *predecessor = block->getSinglePredecessor();
    auto branch = predecessor
                      ? dyn_cast<cf::CondBranchOp>(predecessor->getTerminator())
                      : cf::CondBranchOp();
    if (branch && branch.getTrueDest() != branch.getFalseDest())
      if (FailureOr<TwoStateSlice> slice = sim::buildTwoStateSlice(
              branch.getCondition(), maxDomainBits, maxSliceOps);
          succeeded(slice))
        edge = Edge{branch.getCondition(), branch.getTrueDest() == block,
                    std::move(slice->leaves)};
    auto &entry = edgeCache[block];
    entry = std::move(edge);
    return entry ? &*entry : nullptr;
  }

  static SmallVector<uint64_t> probes(const TwoStateSlice &slice) {
    uint64_t all =
        slice.width >= 64 ? ~uint64_t{0} : (uint64_t{1} << slice.width) - 1;
    SmallVector<uint64_t> result{0, all};
    SmallVector<uint64_t> constants;
    for (Operation *op : slice.ops)
      if (auto constant = dyn_cast<arith::ConstantOp>(op))
        constants.push_back(
            cast<IntegerAttr>(constant.getValue()).getValue().getZExtValue());
    unsigned offset = 0;
    for (Value leaf : slice.leaves) {
      unsigned width = *sim::getTwoStateEvaluationWidth(leaf.getType());
      uint64_t mask = width == 0 ? 0 : ~uint64_t{0} >> (64 - width);
      for (uint64_t constant : constants)
        for (uint64_t value : {constant, constant + 1, constant - 1}) {
          if (result.size() >= maxProbes)
            return result;
          result.push_back((value & mask) << offset);
        }
      offset += width;
    }
    return result;
  }

  DominanceInfo dominance;
  DenseMap<Block *, std::optional<Edge>> edgeCache;
  uint64_t work = 0;
};

class TalosSimFoldSmallDomainsPass final
    : public impl::TalosSimFoldSmallDomainsPassBase<
          TalosSimFoldSmallDomainsPass> {
public:
  void runOnOperation() override {
    sim::SimFuncOp function = getOperation();
    if (function.isExternal())
      return;
    Decider decider(function);
    // Decisions are made on the original body, then applied.
    SmallVector<std::pair<Operation *, bool>> folds;
    function.walk([&](Operation *op) {
      Value condition;
      if (auto branch = dyn_cast<cf::CondBranchOp>(op))
        condition = branch.getCondition();
      else if (auto select = dyn_cast<arith::SelectOp>(op);
               select && select.getCondition().getType().isInteger(1))
        condition = select.getCondition();
      if (!condition || matchPattern(condition, m_Constant()))
        return;
      if (std::optional<bool> value = decider.decide(condition, op->getBlock()))
        folds.push_back({op, *value});
    });
    if (folds.empty())
      return;
    // A decided branch takes one edge and a decided select one operand; the
    // blocks no edge reaches any more are erased, so that later analyses,
    // which skip unreachable code, do not meet their accesses unresolved.
    IRRewriter rewriter(function.getContext());
    for (auto [op, value] : folds) {
      rewriter.setInsertionPoint(op);
      if (auto branch = dyn_cast<cf::CondBranchOp>(op)) {
        rewriter.replaceOpWithNewOp<cf::BranchOp>(
            branch, value ? branch.getTrueDest() : branch.getFalseDest(),
            value ? branch.getTrueDestOperands()
                  : branch.getFalseDestOperands());
        continue;
      }
      auto select = cast<arith::SelectOp>(op);
      rewriter.replaceOp(select, value ? select.getTrueValue()
                                       : select.getFalseValue());
    }
    (void)eraseUnreachableBlocks(rewriter, function->getRegions());
    numFolded += folds.size();
  }
};

} // namespace
} // namespace talos
