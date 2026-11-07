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
// A bounded symbolic proof also handles counts of disjoint masked equalities
// on wider integers. OR alternatives and edge-threaded Boolean phis remain
// one counted item; they do not manufacture additional matches.
// Four-state values are never exhaustively evaluated. Exact case comparisons
// are compared symbolically in both value/unknown planes. Casez additionally
// requires a caller's never-Z certificate for its selector; X stays
// significant. Neither proof removes a four-state no-match check. Possible
// Z wildcards and casex retain their multiple-match reports (12.5.1).
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
#include "talos/Dialect/Simulation/Transforms/FoldSmallDomains.h"
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
/// Predicates in a symbolic pairwise-disjoint match count.
constexpr unsigned maxCountTerms = 64;
constexpr unsigned maxMaskBits = 4096;

/// A branch edge that is the only entry of the block it enters.
struct Edge {
  Value condition;
  bool sense;
  SmallVector<Value> leaves;
};

class Decider {
public:
  explicit Decider(Operation *function,
                   llvm::function_ref<bool(Value)> isNeverZ = {})
      : dominance(function), isNeverZ(isNeverZ) {}

  /// The single value `condition` takes in `block` over every two-state value
  /// of its inputs that the dominating branch edges admit, if there is one.
  std::optional<bool> decide(Value condition, Block *block) {
    if (work > maxFunctionWork)
      return std::nullopt;
    if (auto decided = decideDisjointCount(condition))
      return decided;
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
  struct MaskedEquality {
    Value input;
    APInt mask, value;
  };

  /// Normalize a binary equality to (input & mask) == value. Distinct SSA
  /// loads remain distinct snapshots (IEEE 1800-2023 4.6(a), 10.4.1).
  std::optional<MaskedEquality>
  maskedEquality(Value predicate, unsigned &visited, bool inverted = false) {
    if (++visited > maxSliceOps || ++work > maxFunctionWork)
      return std::nullopt;
    if (auto equal = predicate.getDefiningOp<sim::SimLogicCompareOp>()) {
      bool casez = !inverted && equal.getKind() == sim::CompareKind::CaseZEq;
      if ((!casez && equal.getKind() !=
                         (inverted ? sim::CompareKind::CaseNe
                                   : sim::CompareKind::CaseEq)) ||
          equal.getLhs().getType().getWidth() > maxMaskBits / 2)
        return std::nullopt;
      Value input = equal.getLhs();
      auto literal = equal.getRhs().getDefiningOp<sim::SimLogicConstantOp>();
      if (!literal) {
        input = equal.getRhs();
        literal = equal.getLhs().getDefiningOp<sim::SimLogicConstantOp>();
      }
      if (!literal || (casez && (!isNeverZ || !isNeverZ(input))))
        return std::nullopt;
      // 1800-2023 11.4.5/12.5.1: exact equality compares both planes.
      // A Z-free casez selector has wildcards only in the constant operand;
      // X remains significant. Do not extend this to casex or peel bitwise
      // operations, which can normalize Z to X.
      unsigned width = literal.getValue().getBitWidth();
      APInt significant = APInt::getAllOnes(width);
      if (casez)
        significant &= ~(literal.getValue() & literal.getUnknown());
      APInt mask = significant.zext(width * 2);
      mask.insertBits(significant, width);
      APInt expected = literal.getValue().zext(width * 2);
      expected.insertBits(literal.getUnknown(), width);
      expected &= mask;
      return MaskedEquality{input, std::move(mask), std::move(expected)};
    }
    auto equal = predicate.getDefiningOp<arith::CmpIOp>();
    if (!equal || equal.getPredicate() != (inverted ? arith::CmpIPredicate::ne
                                                    : arith::CmpIPredicate::eq))
      return std::nullopt;
    Value input = equal.getLhs();
    APInt expected;
    if (!matchPattern(equal.getRhs(), m_ConstantInt(&expected))) {
      input = equal.getRhs();
      if (!matchPattern(equal.getLhs(), m_ConstantInt(&expected)))
        return std::nullopt;
    }
    if (!isa<IntegerType>(input.getType()) ||
        expected.getBitWidth() > maxMaskBits)
      return std::nullopt;
    APInt mask = APInt::getAllOnes(expected.getBitWidth());
    while (auto bitAnd = input.getDefiningOp<arith::AndIOp>()) {
      if (++visited > maxSliceOps || ++work > maxFunctionWork)
        return std::nullopt;
      APInt bits;
      if (matchPattern(bitAnd.getRhs(), m_ConstantInt(&bits)))
        input = bitAnd.getLhs();
      else if (matchPattern(bitAnd.getLhs(), m_ConstantInt(&bits)))
        input = bitAnd.getRhs();
      else
        break;
      mask &= bits;
    }
    return MaskedEquality{input, std::move(mask), std::move(expected)};
  }

  /// An overapproximation of the values on which one Boolean term is true.
  /// Alternatives within a term are ORed, not counted as separate matches.
  bool predicateMatches(Value predicate,
                        SmallVectorImpl<MaskedEquality> &matches,
                        unsigned &visited) {
    if (auto equal = maskedEquality(predicate, visited)) {
      if ((equal->value & ~equal->mask).isZero())
        matches.push_back(std::move(*equal));
      return matches.size() <= maxCountTerms;
    }
    if (visited > maxSliceOps || work > maxFunctionWork)
      return false;
    APInt constant;
    if (matchPattern(predicate, m_ConstantInt(&constant)))
      return constant.isZero();
    if (auto either = predicate.getDefiningOp<arith::OrIOp>())
      return predicateMatches(either.getLhs(), matches, visited) &&
             predicateMatches(either.getRhs(), matches, visited);
    if (auto both = predicate.getDefiningOp<arith::AndIOp>()) {
      SmallVector<MaskedEquality> implied;
      if (!predicateMatches(both.getLhs(), implied, visited)) {
        implied.clear();
        if (!predicateMatches(both.getRhs(), implied, visited))
          return false;
      }
      llvm::append_range(matches, std::move(implied));
      return matches.size() <= maxCountTerms;
    }
    auto argument = dyn_cast<BlockArgument>(predicate);
    if (!argument || !argument.getType().isInteger(1))
      return false;
    Block *block = argument.getOwner();
    if (block->getPredecessors().empty())
      return false;
    for (BlockOperand &edge : block->getUses()) {
      if (++visited > maxSliceOps || ++work > maxFunctionWork)
        return false;
      Operation *terminator = edge.getOwner();
      // Do not correlate a loop-carried Boolean with a later iteration.
      if (dominance.dominates(block, terminator->getBlock()))
        return false;
      Value incoming, guard;
      bool inverted = false;
      if (auto branch = dyn_cast<cf::BranchOp>(terminator)) {
        auto operands = branch.getDestOperands();
        if (argument.getArgNumber() >= operands.size())
          return false;
        incoming = operands[argument.getArgNumber()];
      } else if (auto branch = dyn_cast<cf::CondBranchOp>(terminator)) {
        bool trueEdge = edge.getOperandNumber() == 0;
        auto operands = trueEdge ? branch.getTrueDestOperands()
                                 : branch.getFalseDestOperands();
        if (argument.getArgNumber() >= operands.size())
          return false;
        incoming = operands[argument.getArgNumber()];
        guard = branch.getCondition();
        inverted = !trueEdge;
      } else
        return false;
      SmallVector<MaskedEquality> onEdge;
      if (matchPattern(incoming, m_ConstantInt(&constant))) {
        if (constant.isZero())
          continue;
        if (!guard)
          return false;
        auto equal = maskedEquality(guard, visited, inverted);
        if (!equal)
          return false;
        if ((equal->value & ~equal->mask).isZero())
          onEdge.push_back(std::move(*equal));
      } else if (!predicateMatches(incoming, onEdge, visited))
        return false;
      for (auto &equal : onEdge)
        // The edge's snapshot must still be the same SSA value at the use.
        // A definition in the phi block could execute again after that edge.
        if (!dominance.properlyDominates(equal.input.getParentBlock(), block))
          return false;
      llvm::append_range(matches, std::move(onEdge));
      if (matches.size() > maxCountTerms)
        return false;
    }
    return true;
  }

  /// Gather counted occurrences, preserving duplicates and shared subtrees.
  /// Every accepted node is a zero-based sum of Boolean 0/1 values.
  bool countPredicates(Value count, SmallVectorImpl<Value> &predicates,
                       unsigned &visited) {
    if (++visited > maxSliceOps || ++work > maxFunctionWork ||
        predicates.size() > maxCountTerms)
      return false;
    APInt constant;
    if (matchPattern(count, m_ConstantInt(&constant)))
      return constant.isZero();
    if (auto extend = count.getDefiningOp<arith::ExtUIOp>();
        extend && extend.getIn().getType().isInteger(1)) {
      if (predicates.size() == maxCountTerms)
        return false;
      predicates.push_back(extend.getIn());
      return true;
    }
    auto noOverflowFlags = [](arith::AddIOp add) {
      return !add.hasNoSignedWrap() && !add.hasNoUnsignedWrap();
    };
    if (auto select = count.getDefiningOp<arith::SelectOp>()) {
      auto increment = select.getTrueValue().getDefiningOp<arith::AddIOp>();
      if (!increment || !noOverflowFlags(increment))
        return false;
      Value previous = select.getFalseValue();
      bool addsOne = (increment.getLhs() == previous &&
                      matchPattern(increment.getRhs(), m_One())) ||
                     (increment.getRhs() == previous &&
                      matchPattern(increment.getLhs(), m_One()));
      if (!addsOne || !countPredicates(previous, predicates, visited) ||
          predicates.size() >= maxCountTerms)
        return false;
      predicates.push_back(select.getCondition());
      return true;
    }
    if (auto add = count.getDefiningOp<arith::AddIOp>();
        add && noOverflowFlags(add))
      return countPredicates(add.getLhs(), predicates, visited) &&
             countPredicates(add.getRhs(), predicates, visited);
    return false;
  }

public:
  /// IEEE 1800-2023 12.4.2/12.5.3: prove a multiple-match report unreachable
  /// from its actual binary predicates, without assuming a unique qualifier.
  /// Equalities conflict when they constrain a common bit differently.
  /// This also handles wide masked decoders beyond the exhaustive budget.
  /// It proves only an upper bound; a no-match report remains independent.
  std::optional<bool> decideDisjointCount(Value condition) {
    auto compare = condition.getDefiningOp<arith::CmpIOp>();
    if (!compare || !matchPattern(compare.getRhs(), m_One()))
      return std::nullopt;
    auto predicate = compare.getPredicate();
    bool signedCount = predicate == arith::CmpIPredicate::sgt ||
                       predicate == arith::CmpIPredicate::sle;
    bool greater = signedCount ? predicate == arith::CmpIPredicate::sgt
                               : predicate == arith::CmpIPredicate::ugt;
    if (!signedCount && predicate != arith::CmpIPredicate::ugt &&
        predicate != arith::CmpIPredicate::ule)
      return std::nullopt;
    auto type = dyn_cast<IntegerType>(compare.getLhs().getType());
    if (!type || type.getWidth() < 2)
      return std::nullopt;
    SmallVector<Value> predicates;
    unsigned visited = 0;
    if (!countPredicates(compare.getLhs(), predicates, visited) ||
        APInt(64, predicates.size()).getActiveBits() >
            type.getWidth() - unsigned(signedCount))
      return std::nullopt;
    SmallVector<SmallVector<MaskedEquality>> matches;
    uint64_t startWork = work;
    for (Value counted : predicates) {
      SmallVector<MaskedEquality> alternatives;
      if (!predicateMatches(counted, alternatives, visited))
        return std::nullopt;
      for (const auto &previous : matches)
        for (const auto &equal : alternatives)
          for (const auto &other : previous) {
            work += (equal.mask.getBitWidth() + 63) / 64;
            if (work > maxFunctionWork || work - startWork > maxConditionWork ||
                equal.input != other.input ||
                ((equal.value ^ other.value) & equal.mask & other.mask)
                    .isZero())
              return std::nullopt;
          }
      matches.push_back(std::move(alternatives));
    }
    return !greater;
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
  llvm::function_ref<bool(Value)> isNeverZ;
};

unsigned foldConditions(sim::SimFuncOp function, Decider &decider,
                        bool countsOnly) {
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
    auto value = countsOnly ? decider.decideDisjointCount(condition)
                            : decider.decide(condition, op->getBlock());
    if (value)
      folds.push_back({op, *value});
  });
  if (folds.empty())
    return 0;
  IRRewriter rewriter(function.getContext());
  for (auto [op, value] : folds) {
    rewriter.setInsertionPoint(op);
    if (auto branch = dyn_cast<cf::CondBranchOp>(op)) {
      rewriter.replaceOpWithNewOp<cf::BranchOp>(
          branch, value ? branch.getTrueDest() : branch.getFalseDest(),
          value ? branch.getTrueDestOperands() : branch.getFalseDestOperands());
      continue;
    }
    auto select = cast<arith::SelectOp>(op);
    rewriter.replaceOp(select, value ? select.getTrueValue()
                                   : select.getFalseValue());
  }
  (void)eraseUnreachableBlocks(rewriter, function->getRegions());
  return folds.size();
}

class TalosSimFoldSmallDomainsPass final
    : public impl::TalosSimFoldSmallDomainsPassBase<
          TalosSimFoldSmallDomainsPass> {
public:
  void runOnOperation() override {
    sim::SimFuncOp function = getOperation();
    if (function.isExternal())
      return;
    Decider decider(function);
    numFolded += foldConditions(function, decider, /*countsOnly=*/false);
  }
};

} // namespace

unsigned foldDisjointMatchCounts(
    sim::SimFuncOp function, llvm::function_ref<bool(Value)> isNeverZ) {
  if (function.isExternal())
    return 0;
  Decider decider(function, isNeverZ);
  return foldConditions(function, decider, /*countsOnly=*/true);
}
} // namespace talos
