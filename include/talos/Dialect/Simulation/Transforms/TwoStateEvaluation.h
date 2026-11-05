//===- TwoStateEvaluation.h - Two-state slice evaluation --------*- C++ -*-===//
//
// Evaluates the pure operations computing some values from two-state leaves
// (block arguments and results of operations it does not interpret) for
// given leaf values, bit-exactly. Four-state values are never leaves, and a
// result that would be poison makes the evaluation fail.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_SIMULATION_TRANSFORMS_TWOSTATEEVALUATION_H
#define TALOS_DIALECT_SIMULATION_TRANSFORMS_TWOSTATEEVALUATION_H

#include "mlir/IR/Operation.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include <optional>

namespace talos::sim {

/// The bit width of a two-state value the evaluator models: a signless
/// integer, or a packed aggregate without four-state leaves, modeled as its
/// packed bit image.
std::optional<unsigned> getTwoStateEvaluationWidth(mlir::Type type);

/// The operations computing `roots` from leaves, in dependence order.
struct TwoStateSlice {
  llvm::SmallVector<mlir::Value> leaves;
  llvm::SmallVector<mlir::Operation *> ops;
  /// Total width of the leaves.
  uint64_t width = 0;
};

/// Collects the slice of `roots`. Fails when the leaves exceed `maxLeafBits`
/// in total, the slice exceeds `maxOps` operations, or a value the evaluator
/// does not model is reached.
mlir::FailureOr<TwoStateSlice>
buildTwoStateSlice(mlir::ArrayRef<mlir::Value> roots, uint64_t maxLeafBits,
                   unsigned maxOps);

/// Evaluates one slice for leaf assignments.
class TwoStateEvaluator {
public:
  explicit TwoStateEvaluator(const TwoStateSlice &slice);

  /// Evaluates with the leaves taken, in order, from the low bits of
  /// `assignment` upward. Requires a slice of at most 64 leaf bits.
  mlir::LogicalResult run(uint64_t assignment);
  /// Evaluates with explicit leaf values, one per leaf.
  mlir::LogicalResult run(mlir::ArrayRef<llvm::APInt> leafValues);

  /// The value of `value`, which must be a leaf or a slice result.
  const llvm::APInt &get(mlir::Value value) const {
    return values[slots.at(value)];
  }

private:
  struct Step {
    mlir::Operation *op;
    unsigned result;
    unsigned width;
    llvm::SmallVector<unsigned, 3> operands;
    /// The bit offset of an aggregate.extract member.
    uint64_t offset = 0;
  };
  mlir::LogicalResult evaluate(const Step &step);

  llvm::SmallVector<unsigned> leafWidths;
  llvm::SmallVector<Step> steps;
  llvm::DenseMap<mlir::Value, unsigned> slots;
  llvm::SmallVector<llvm::APInt> values;
};

} // namespace talos::sim

#endif
