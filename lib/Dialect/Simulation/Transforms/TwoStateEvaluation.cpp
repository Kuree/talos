//===- TwoStateEvaluation.cpp - Exact evaluation of two-state slices ------===//

#include "talos/Dialect/Simulation/Transforms/TwoStateEvaluation.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace talos::sim {

std::optional<unsigned> getTwoStateEvaluationWidth(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() ? std::optional<unsigned>(integer.getWidth())
                                : std::nullopt;
  if (isa<PackedArrayType, PackedStructType>(type) &&
      !containsFourStateLeaf(type))
    return getPackedWidth(type);
  return std::nullopt;
}

namespace {
/// Whether the evaluator interprets `op` exactly on two-state bits. Results
/// that may be poison through overflow flags are not interpreted.
bool isEvaluable(Operation *op) {
  if (!isa<arith::ConstantOp, arith::AndIOp, arith::OrIOp, arith::XOrIOp,
           arith::AddIOp, arith::SubIOp, arith::MulIOp, arith::ShLIOp,
           arith::ShRUIOp, arith::ShRSIOp, arith::ExtUIOp, arith::ExtSIOp,
           arith::TruncIOp, arith::CmpIOp, arith::SelectOp, SimPackedFlattenOp,
           SimPackedUnflattenOp, SimAggregateExtractOp>(op))
    return false;
  if (auto flags = dyn_cast<arith::ArithIntegerOverflowFlagsInterface>(op))
    if (flags.hasNoSignedWrap() || flags.hasNoUnsignedWrap())
      return false;
  if (auto constant = dyn_cast<arith::ConstantOp>(op))
    if (!isa<IntegerAttr>(constant.getValue()))
      return false;
  if (auto extract = dyn_cast<SimAggregateExtractOp>(op))
    if (!isa<PackedArrayType, PackedStructType>(extract.getInput().getType()))
      return false;
  auto modeled = [](Value value) {
    return getTwoStateEvaluationWidth(value.getType()).has_value();
  };
  return llvm::all_of(op->getOperands(), modeled) &&
         llvm::all_of(op->getResults(), modeled);
}
} // namespace

FailureOr<TwoStateSlice> buildTwoStateSlice(ArrayRef<Value> roots,
                                            uint64_t maxLeafBits,
                                            unsigned maxOps) {
  TwoStateSlice slice;
  llvm::SmallPtrSet<Operation *, 32> done;
  llvm::SmallPtrSet<Value, 8> leaves;
  // Iterative post-order over (operation, next operand) frames.
  SmallVector<std::pair<Operation *, unsigned>> stack;
  auto visit = [&](Value value) -> LogicalResult {
    Operation *op = value.getDefiningOp();
    if (op && isEvaluable(op)) {
      if (!done.contains(op))
        stack.push_back({op, 0});
      return success();
    }
    std::optional<unsigned> width = getTwoStateEvaluationWidth(value.getType());
    if (!width)
      return failure();
    if (leaves.insert(value).second) {
      slice.width += *width;
      if (slice.width > maxLeafBits)
        return failure();
      slice.leaves.push_back(value);
    }
    return success();
  };
  for (Value root : roots) {
    if (failed(visit(root)))
      return failure();
    while (!stack.empty()) {
      auto [op, next] = stack.back();
      if (done.contains(op)) {
        stack.pop_back();
        continue;
      }
      if (next < op->getNumOperands()) {
        ++stack.back().second;
        if (failed(visit(op->getOperand(next))))
          return failure();
        continue;
      }
      done.insert(op);
      slice.ops.push_back(op);
      if (slice.ops.size() > maxOps)
        return failure();
      stack.pop_back();
    }
  }
  return slice;
}

TwoStateEvaluator::TwoStateEvaluator(const TwoStateSlice &slice) {
  for (Value leaf : slice.leaves) {
    slots[leaf] = leafWidths.size();
    leafWidths.push_back(*getTwoStateEvaluationWidth(leaf.getType()));
  }
  unsigned next = slice.leaves.size();
  for (Operation *op : slice.ops) {
    Step step{
        op, next, *getTwoStateEvaluationWidth(op->getResult(0).getType()), {}};
    for (Value operand : op->getOperands())
      step.operands.push_back(slots.at(operand));
    if (auto extract = dyn_cast<SimAggregateExtractOp>(op)) {
      auto member = getAggregateProvenanceSubelement(
          extract.getInput().getType(), extract.getIndex());
      // A member the layout cannot place is evaluated as a failure.
      step.offset =
          member && member->second == step.width ? member->first : UINT64_MAX;
    }
    slots[op->getResult(0)] = next++;
    steps.push_back(std::move(step));
  }
  values.resize(next);
}

LogicalResult TwoStateEvaluator::run(uint64_t assignment) {
  unsigned offset = 0;
  for (auto [index, width] : llvm::enumerate(leafWidths)) {
    values[index] =
        APInt(width, width == 0 ? 0
                                : (assignment >> offset) &
                                      (~uint64_t{0} >> (64 - width)));
    offset += width;
  }
  for (const Step &step : steps)
    if (failed(evaluate(step)))
      return failure();
  return success();
}

LogicalResult TwoStateEvaluator::run(ArrayRef<APInt> leafValues) {
  if (leafValues.size() != leafWidths.size())
    return failure();
  for (auto [index, value] : llvm::enumerate(leafValues)) {
    if (value.getBitWidth() != leafWidths[index])
      return failure();
    values[index] = value;
  }
  for (const Step &step : steps)
    if (failed(evaluate(step)))
      return failure();
  return success();
}

LogicalResult TwoStateEvaluator::evaluate(const Step &step) {
  auto operand = [&](unsigned index) -> const APInt & {
    return values[step.operands[index]];
  };
  APInt &result = values[step.result];
  unsigned width = step.width;
  return llvm::TypeSwitch<Operation *, LogicalResult>(step.op)
      .Case([&](arith::ConstantOp constant) {
        result = cast<IntegerAttr>(constant.getValue()).getValue();
        return success();
      })
      .Case([&](arith::AndIOp) {
        result = operand(0) & operand(1);
        return success();
      })
      .Case([&](arith::OrIOp) {
        result = operand(0) | operand(1);
        return success();
      })
      .Case([&](arith::XOrIOp) {
        result = operand(0) ^ operand(1);
        return success();
      })
      .Case([&](arith::AddIOp) {
        result = operand(0) + operand(1);
        return success();
      })
      .Case([&](arith::SubIOp) {
        result = operand(0) - operand(1);
        return success();
      })
      .Case([&](arith::MulIOp) {
        result = operand(0) * operand(1);
        return success();
      })
      .Case<arith::ShLIOp, arith::ShRUIOp, arith::ShRSIOp>([&](auto shift) {
        // An amount of at least the width yields poison.
        const APInt &amount = operand(1);
        if (amount.uge(width))
          return failure();
        unsigned bits = amount.getZExtValue();
        if (isa<arith::ShLIOp>(shift))
          result = operand(0).shl(bits);
        else if (isa<arith::ShRUIOp>(shift))
          result = operand(0).lshr(bits);
        else
          result = operand(0).ashr(bits);
        return success();
      })
      .Case([&](arith::ExtUIOp) {
        result = operand(0).zext(width);
        return success();
      })
      .Case([&](arith::ExtSIOp) {
        result = operand(0).sext(width);
        return success();
      })
      .Case([&](arith::TruncIOp) {
        result = operand(0).trunc(width);
        return success();
      })
      .Case([&](arith::CmpIOp compare) {
        result = APInt(1, arith::applyCmpPredicate(compare.getPredicate(),
                                                   operand(0), operand(1)));
        return success();
      })
      .Case([&](arith::SelectOp) {
        result = operand(0).getBoolValue() ? operand(1) : operand(2);
        return success();
      })
      .Case<SimPackedFlattenOp, SimPackedUnflattenOp>([&](auto) {
        // Both views keep the packed bit image.
        if (operand(0).getBitWidth() != width)
          return failure();
        result = operand(0);
        return success();
      })
      .Case([&](SimAggregateExtractOp) {
        if (step.offset == UINT64_MAX ||
            step.offset + width > operand(0).getBitWidth())
          return failure();
        result = operand(0).extractBits(width, step.offset);
        return success();
      })
      .Default([](Operation *) { return failure(); });
}

} // namespace talos::sim
