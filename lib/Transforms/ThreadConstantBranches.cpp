//===- ThreadConstantBranches.cpp - Branch past constant decisions -------===//
//
// A predicate answered on several paths merges its answers in a block
// argument:
//
//   ^head: llvm.cond_br %clean, ^decide(%true), ^slow
//   ^slow: ... llvm.br ^decide(%answer)
//   ^decide(%known: i1): llvm.cond_br %known, ^copy, ^body
//
// When the merge block holds only its branch, each edge whose operands decide
// that branch goes to the chosen successor instead:
//
//   ^head: llvm.cond_br %clean, ^copy, ^slow
//
//===----------------------------------------------------------------------===//

#include "talos/Transforms/Passes.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_TALOSTHREADCONSTANTBRANCHESPASS
#include "talos/Transforms/Passes.h.inc"

namespace {
/// The successor index `branch` takes for operand constants `operands` (null
/// where unknown), if exactly one successor slot leads to that block.
std::optional<unsigned> chosenSuccessor(BranchOpInterface branch,
                                        ArrayRef<Attribute> operands) {
  Block *target = nullptr;
  // llvm.cond_br keeps the interface's default, which decides nothing.
  if (auto conditional = dyn_cast<LLVM::CondBrOp>(branch.getOperation())) {
    auto condition = dyn_cast_or_null<IntegerAttr>(operands.front());
    if (!condition)
      return std::nullopt;
    target = condition.getValue().isZero() ? conditional.getFalseDest()
                                           : conditional.getTrueDest();
  } else {
    target = branch.getSuccessorForOperands(operands);
  }
  if (!target)
    return std::nullopt;
  std::optional<unsigned> index;
  for (unsigned successor = 0; successor != branch->getNumSuccessors();
       ++successor)
    if (branch->getSuccessor(successor) == target) {
      if (index)
        return std::nullopt;
      index = successor;
    }
  return index;
}

using Edge = std::pair<Operation *, unsigned>;

/// On-demand SSA reconstruction (Braun et al., "Simple and Efficient
/// Construction of Static Single Assignment Form", CC 2013) for one value
/// whose definition no longer dominates its uses: `value`, an argument of
/// `home`, holds at `home`, and each edge that now bypasses `home` carries
/// its own definition. Blocks entered with differing definitions receive a
/// block argument that every incoming edge supplies. A conditional branch on
/// the value itself fixes it along each of its edges. Code no longer
/// reachable from the entry is dominated by every value and constrains
/// nothing.
class ValueRepair {
public:
  ValueRepair(Value value, Block *home, DenseMap<Edge, Value> bypass,
              const DenseSet<Block *> &reachable, RewriterBase &rewriter)
      : value(value), home(home), bypass(std::move(bypass)),
        reachable(reachable), rewriter(rewriter) {}

  /// The definition reaching the entry of `block`, a block of home's region.
  Value atEntry(Block *block) {
    SmallVector<Block *> chain;
    Value found;
    for (Block *current = block;;) {
      if (current == home) {
        found = value;
        break;
      }
      if (Value known = entries.lookup(current)) {
        found = known;
        break;
      }
      if (!reachable.contains(current)) {
        found = value;
        break;
      }
      auto edges = current->getUses();
      if (!llvm::hasSingleElement(edges)) {
        found = merge(current);
        break;
      }
      chain.push_back(current);
      BlockOperand &edge = *edges.begin();
      if (Value carried = implied(edge)) {
        found = carried;
        break;
      }
      current = edge.getOwner()->getBlock();
    }
    for (Block *walked : chain)
      remember(walked, found);
    return found;
  }

private:
  void remember(Block *block, Value definition) {
    entries[block] = definition;
    holders[definition].push_back(block);
  }

  static Edge key(BlockOperand &edge) {
    return {edge.getOwner(), edge.getOperandNumber()};
  }

  /// The definition `edge` itself fixes: the one a bypassing edge carries,
  /// or the outcome of a conditional branch on the value.
  Value implied(BlockOperand &edge) {
    if (Value carried = bypass.lookup(key(edge)))
      return carried;
    Operation *owner = edge.getOwner();
    Value condition;
    Block *taken = nullptr, *other = nullptr;
    if (auto branch = dyn_cast<LLVM::CondBrOp>(owner)) {
      condition = branch.getCondition();
      taken = branch.getTrueDest();
      other = branch.getFalseDest();
    } else if (auto branch = dyn_cast<cf::CondBranchOp>(owner)) {
      condition = branch.getCondition();
      taken = branch.getTrueDest();
      other = branch.getFalseDest();
    }
    if (condition != value || taken == other)
      return {};
    Type type = value.getType();
    return constant(
        rewriter.getIntegerAttr(type, edge.getOperandNumber() == 0 ? 1 : 0));
  }

  /// A constant of `attribute` in the region's entry block, which dominates
  /// every use; null if the dialect cannot materialize it.
  Value constant(Attribute attribute) {
    auto [cached, inserted] = constants.try_emplace(attribute, Value{});
    if (!inserted)
      return cached->second;
    OpBuilder::InsertionGuard guard(rewriter);
    rewriter.setInsertionPointToStart(&home->getParent()->front());
    if (Operation *materialized =
            home->getTerminator()->getDialect()->materializeConstant(
                rewriter, attribute, value.getType(), value.getLoc()))
      cached->second = materialized->getResult(0);
    return cached->second;
  }

  Value along(BlockOperand &edge) {
    if (Value carried = implied(edge))
      return carried;
    Block *source = edge.getOwner()->getBlock();
    return source == home ? value : atEntry(source);
  }

  Value merge(Block *block) {
    BlockArgument merged = block->addArgument(value.getType(), value.getLoc());
    remember(block, merged);
    SmallVector<BlockOperand *> edges = llvm::map_to_vector(
        block->getUses(), [](BlockOperand &edge) { return &edge; });
    // The distinct definitions arriving from reachable predecessors, and
    // their common constant if every one is a constant of one attribute.
    SmallVector<Value> incomings;
    for (BlockOperand *edge : edges) {
      Value incoming = reachable.contains(edge->getOwner()->getBlock())
                           ? along(*edge)
                           : merged;
      auto branch = cast<BranchOpInterface>(edge->getOwner());
      rewriter.modifyOpInPlace(branch, [&] {
        branch.getSuccessorOperands(edge->getOperandNumber()).append(incoming);
      });
      if (incoming != merged && !llvm::is_contained(incomings, incoming))
        incomings.push_back(incoming);
    }
    Value same;
    if (incomings.size() == 1) {
      same = incomings.front();
    } else if (!incomings.empty()) {
      Attribute common;
      bool constant = llvm::all_of(incomings, [&](Value incoming) {
        Attribute attribute;
        if (!matchPattern(incoming, m_Constant(&attribute)) ||
            (common && attribute != common))
          return false;
        common = attribute;
        return true;
      });
      // Equal constants defined in different predecessors: none of them
      // need dominate this block, a copy in the entry block does.
      if (constant)
        same = this->constant(common);
    }
    if (!same)
      return merged;
    for (BlockOperand *edge : edges) {
      auto branch = cast<BranchOpInterface>(edge->getOwner());
      rewriter.modifyOpInPlace(branch, [&] {
        SuccessorOperands operands =
            branch.getSuccessorOperands(edge->getOperandNumber());
        operands.erase(operands.size() - 1);
      });
    }
    rewriter.replaceAllUsesWith(merged, same);
    block->eraseArgument(merged.getArgNumber());
    // Erased arguments' storage is reused: forget every reference to it.
    for (Block *holder : holders.lookup(merged))
      if (entries.lookup(holder) == merged)
        remember(holder, same);
    holders.erase(merged);
    return same;
  }

  Value value;
  Block *home;
  DenseMap<Edge, Value> bypass;
  const DenseSet<Block *> &reachable;
  RewriterBase &rewriter;
  DenseMap<Block *, Value> entries;
  /// The blocks whose cached definition is each value.
  DenseMap<Value, SmallVector<Block *>> holders;
  DenseMap<Attribute, Value> constants;
};

/// The blocks of `region` reachable from its entry.
DenseSet<Block *> reachableBlocks(Region &region) {
  DenseSet<Block *> reachable;
  SmallVector<Block *> worklist{&region.front()};
  reachable.insert(&region.front());
  while (!worklist.empty())
    for (Block *successor : worklist.pop_back_val()->getSuccessors())
      if (reachable.insert(successor).second)
        worklist.push_back(successor);
  return reachable;
}

/// Whether every edge of `region` forwards all its operands, so a repair can
/// pass a value along any of them.
bool forwardsEveryEdge(Region &region) {
  for (Block &block : region) {
    Operation *terminator = block.getTerminator();
    if (!terminator || terminator->getNumSuccessors() == 0)
      continue;
    auto branch = dyn_cast<BranchOpInterface>(terminator);
    if (!branch)
      return false;
    for (unsigned successor = 0; successor != terminator->getNumSuccessors();
         ++successor)
      if (branch.getSuccessorOperands(successor).getProducedOperandCount())
        return false;
  }
  return true;
}

/// Redirects the deciding edges into a block that holds only `branch`. An
/// argument of the block used elsewhere (a merged flag later blocks test
/// again) is repaired on the paths that now bypass it.
struct ThreadConstantDecision final
    : OpInterfaceRewritePattern<BranchOpInterface> {
  using OpInterfaceRewritePattern::OpInterfaceRewritePattern;

  /// Rewrites only add forwarded operands, so the answer per region holds.
  bool repairable(Region &region) const {
    auto [entry, inserted] = repairableRegions.try_emplace(&region, false);
    if (inserted)
      entry->second = forwardsEveryEdge(region);
    return entry->second;
  }
  mutable DenseMap<Region *, bool> repairableRegions;

  LogicalResult matchAndRewrite(BranchOpInterface branch,
                                PatternRewriter &rewriter) const override {
    Block *block = branch->getBlock();
    if (&block->front() != branch.getOperation() || block->isEntryBlock() ||
        block->getNumArguments() == 0)
      return failure();
    // The branch's own successor operands must all be forwarded values.
    for (unsigned successor = 0; successor != branch->getNumSuccessors();
         ++successor)
      if (branch.getSuccessorOperands(successor).getProducedOperandCount())
        return failure();
    SmallVector<BlockArgument> escaping;
    for (BlockArgument argument : block->getArguments())
      if (llvm::any_of(argument.getUsers(), [&](Operation *user) {
            return user != branch.getOperation();
          }))
        escaping.push_back(argument);
    if (!escaping.empty() && !repairable(*block->getParent()))
      return failure();

    // Per escaping argument, the value each bypassing edge carries.
    SmallVector<DenseMap<Edge, Value>> bypass(escaping.size());
    bool changed = false;
    for (BlockOperand &use : llvm::make_early_inc_range(block->getUses())) {
      Operation *predecessor = use.getOwner();
      auto edge = dyn_cast<BranchOpInterface>(predecessor);
      if (!edge || predecessor == branch.getOperation())
        continue;
      unsigned incoming = use.getOperandNumber();
      SuccessorOperands arguments = edge.getSuccessorOperands(incoming);
      if (arguments.getProducedOperandCount() != 0 ||
          arguments.size() != block->getNumArguments())
        continue;
      // A loop latch passing the block's own arguments back means their
      // values at the latch, which the bypass itself may change.
      if (llvm::any_of(arguments.getForwardedOperands(), [&](Value operand) {
            auto argument = dyn_cast<BlockArgument>(operand);
            return argument && argument.getOwner() == block;
          }))
        continue;
      // The block defines nothing but its arguments: every other value
      // dominates it, and with it each predecessor's terminator.
      auto onEdge = [&](Value value) {
        auto argument = dyn_cast<BlockArgument>(value);
        return argument && argument.getOwner() == block
                   ? arguments[argument.getArgNumber()]
                   : value;
      };
      SmallVector<Attribute> constants;
      for (Value operand : branch->getOperands()) {
        Attribute constant;
        (void)matchPattern(onEdge(operand), m_Constant(&constant));
        constants.push_back(constant);
      }
      std::optional<unsigned> successor = chosenSuccessor(branch, constants);
      if (!successor || branch->getSuccessor(*successor) == block)
        continue;
      SmallVector<Value> forwarded = llvm::map_to_vector(
          branch.getSuccessorOperands(*successor).getForwardedOperands(),
          onEdge);
      for (auto [index, argument] : llvm::enumerate(escaping))
        bypass[index][{predecessor, incoming}] = onEdge(argument);
      Block *target = branch->getSuccessor(*successor);
      rewriter.modifyOpInPlace(predecessor, [&] {
        predecessor->setSuccessor(target, incoming);
        arguments.getMutableForwardedOperands().assign(forwarded);
      });
      changed = true;
    }
    if (!changed)
      return failure();
    if (escaping.empty())
      return success();
    Region &region = *block->getParent();
    DenseSet<Block *> reachable = reachableBlocks(region);
    for (auto [index, argument] : llvm::enumerate(escaping)) {
      ValueRepair repair(argument, block, std::move(bypass[index]), reachable,
                         rewriter);
      // The block of home's region holding a use, also of a nested op.
      auto useBlock = [&](OpOperand &use) {
        return region.findAncestorBlockInRegion(*use.getOwner()->getBlock());
      };
      // Settle the definition reaching every block that uses the argument.
      // Merges append operands as they go, which can add uses (and moves
      // operand storage), so look again until no new block appears.
      DenseSet<Block *> settled;
      for (bool grew = true; grew;) {
        grew = false;
        SmallVector<Block *> pending;
        for (OpOperand &use : argument.getUses())
          if (use.getOwner() != branch.getOperation())
            if (Block *owner = useBlock(use); !settled.contains(owner))
              pending.push_back(owner);
        for (Block *owner : pending)
          if (settled.insert(owner).second) {
            (void)repair.atEntry(owner);
            grew = true;
          }
      }
      // Every block is settled, so these queries change no operand list.
      for (OpOperand &use : llvm::make_early_inc_range(argument.getUses())) {
        if (use.getOwner() == branch.getOperation())
          continue;
        Value reaching = repair.atEntry(useBlock(use));
        if (reaching != argument)
          rewriter.modifyOpInPlace(use.getOwner(), [&] { use.set(reaching); });
      }
    }
    return success();
  }
};

/// `llvm.cond_br` on a constant takes one edge; cf.cond_br has this as a
/// canonicalization pattern, the LLVM dialect has none.
struct FoldConstantCondition final : OpRewritePattern<LLVM::CondBrOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LLVM::CondBrOp branch,
                                PatternRewriter &rewriter) const override {
    APInt condition;
    if (!matchPattern(branch.getCondition(), m_ConstantInt(&condition)))
      return failure();
    bool taken = !condition.isZero();
    rewriter.replaceOpWithNewOp<LLVM::BrOp>(
        branch,
        taken ? branch.getTrueDestOperands() : branch.getFalseDestOperands(),
        taken ? branch.getTrueDest() : branch.getFalseDest());
    return success();
  }
};

struct TalosThreadConstantBranchesPass final
    : impl::TalosThreadConstantBranchesPassBase<
          TalosThreadConstantBranchesPass> {
  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<ThreadConstantDecision, FoldConstantCondition>(&getContext());
    // Only redirect edges and repair their values here: folding, constant
    // uniquing and dropping the bypassed blocks belong to the canonicalizer.
    GreedyRewriteConfig config;
    config.enableFolding(false)
        .enableConstantCSE(false)
        .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
    // Each rewrite only moves an edge forward, but constants circulating in a
    // loop of decision blocks can keep moving it; stopping at the iteration
    // limit still leaves every edge valid.
    (void)applyPatternsGreedily(getOperation(), std::move(patterns), config);
  }
};
} // namespace
} // namespace talos
