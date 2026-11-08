//===- KnownCasts.h - Two-state views of known values -----------*- C++ -*-===//

#ifndef TALOS_LIB_DIALECT_SCHEDULE_TRANSFORMS_KNOWNCASTS_H
#define TALOS_LIB_DIALECT_SCHEDULE_TRANSFORMS_KNOWNCASTS_H

#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace talos::detail {

/// The LRM two-state conversion, exact for a known value (IEEE 1800-2023
/// 6.11.2 maps only X/Z bits to 0). `value` must be a four-state scalar or a
/// packed aggregate (KnownVersioningAnalysis::isCastable).
inline mlir::Value castKnown(mlir::OpBuilder &builder, mlir::Location loc,
                             mlir::Value value) {
  mlir::Type type = value.getType();
  if (auto logic = mlir::dyn_cast<sim::LogicType>(type)) {
    mlir::Value bits = sim::SimLogicToBitsOp::create(
        builder, loc, builder.getIntegerType(logic.getWidth()), value);
    return sim::SimLogicFromBitsOp::create(builder, loc, logic, bits);
  }
  mlir::Type scalar = sim::getPackedScalarType(type);
  mlir::Value flat =
      sim::SimPackedFlattenOp::create(builder, loc, scalar, value);
  return sim::SimPackedUnflattenOp::create(builder, loc, type,
                                           castKnown(builder, loc, flat));
}

/// Reuse registered value canonicalizations after exposing a specialization's
/// known views. Keep this pattern set immutable and shared by function workers.
inline mlir::FrozenRewritePatternSet
knownValuePatterns(mlir::MLIRContext *context) {
  mlir::RewritePatternSet patterns(context);
  for (llvm::StringRef name : {"arith", "math", "simulation"}) {
    if (mlir::Dialect *dialect = context->getLoadedDialect(name))
      dialect->getCanonicalizationPatterns(patterns);
    for (mlir::RegisteredOperationName operation :
         context->getRegisteredOperationsByDialect(name)) {
      // Root purity is insufficient here: aggregate/ref canonicalizers can
      // introduce new accesses or rewrite existing ones. Those rewrites do
      // not preserve this late stage's access certificates and inventories.
      // Scalar logic rules and packed inverse-view folds only rewrite values.
      llvm::StringRef operationName = operation.getStringRef();
      if (name == "simulation" &&
          !operationName.starts_with("simulation.logic.") &&
          !operationName.starts_with("simulation.bits.") &&
          operationName != sim::SimPackedFlattenOp::getOperationName() &&
          operationName != sim::SimPackedUnflattenOp::getOperationName())
        continue;
      operation.getCanonicalizationPatterns(patterns, context);
    }
  }
  return mlir::FrozenRewritePatternSet(std::move(patterns));
}

/// Expose already established scalar facts without changing storage or the
/// call ABI. Collect facts before rewriting, so no query sees a new SSA value.
inline void
exposeKnownScalars(sim::SimFuncOp function,
                   llvm::function_ref<bool(mlir::Value)> provenKnown) {
  llvm::SmallVector<mlir::Value> known;
  auto collect = [&](mlir::Value value) {
    // As in packed lowering, a live-state invariant does not certify a
    // Preponed snapshot or a history ring's initial X entries.
    if (mlir::isa_and_nonnull<sim::SimSampledReadOp, sim::SimSampledHistoryOp,
                              sim::SimClockedSampleReadOp>(
            value.getDefiningOp()))
      return;
    auto type = mlir::dyn_cast<sim::LogicType>(value.getType());
    if (!type || type.getWidth() > 64 || !provenKnown(value))
      return;
    mlir::Operation *producer = value.getDefiningOp();
    if (mlir::isa_and_nonnull<sim::SimLogicFromBitsOp, sim::SimLogicConstantOp>(
            producer))
      return;
    // Seed the proof's boundaries, then let the existing operator patterns
    // propagate integer views. Casting every already-known intermediate
    // obscures those chains and needlessly grows the typed graph.
    bool boundary = !producer || !mlir::isMemoryEffectFree(producer) ||
                    producer->getDialect()->getNamespace() != "simulation";
    if (producer)
      for (mlir::Value input : producer->getOperands()) {
        if (!sim::containsFourStateLeaf(input.getType()))
          continue;
        auto scalar = mlir::dyn_cast<sim::LogicType>(input.getType());
        boundary |= !scalar || scalar.getWidth() > 64 || !provenKnown(input);
      }
    if (boundary)
      known.push_back(value);
  };
  for (mlir::Block &block : function.getBody()) {
    for (mlir::BlockArgument argument : block.getArguments())
      collect(argument);
    for (mlir::Operation &operation : block)
      for (mlir::Value result : operation.getResults())
        collect(result);
  }
  mlir::OpBuilder builder(function.getContext());
  for (mlir::Value value : known) {
    if (auto result = mlir::dyn_cast<mlir::OpResult>(value))
      builder.setInsertionPointAfter(result.getOwner());
    else
      builder.setInsertionPointToStart(
          mlir::cast<mlir::BlockArgument>(value).getOwner());
    mlir::Value cast = castKnown(builder, function.getLoc(), value);
    mlir::Operation *first =
        cast.getDefiningOp()->getOperand(0).getDefiningOp();
    value.replaceAllUsesExcept(cast, first);
  }
}

/// Fold the typed value graph before it expands into two native planes.
/// Planned fragments name blocks by ordinal: do not simplify control flow or
/// enqueue effectful accesses. In particular a known store must remain an
/// access carrying its certificate, not become an explicit zero-plane store.
inline mlir::LogicalResult
canonicalizeKnownValues(sim::SimFuncOp function,
                        const mlir::FrozenRewritePatternSet &patterns) {
  llvm::SmallVector<mlir::Operation *> values;
  function.walk([&](mlir::Operation *operation) {
    if (operation->getNumRegions() || operation->getNumResults() != 1 ||
        operation->hasTrait<mlir::OpTrait::IsTerminator>() ||
        !mlir::isMemoryEffectFree(operation))
      return;
    mlir::Type type = operation->getResult(0).getType();
    if (mlir::isa<mlir::IntegerType, sim::LogicType>(type) ||
        sim::getPackedScalarType(type))
      values.push_back(operation);
  });
  mlir::GreedyRewriteConfig config;
  config.setStrictness(mlir::GreedyRewriteStrictness::ExistingAndNewOps)
      .setRegionSimplificationLevel(mlir::GreedySimplifyRegionLevel::Disabled);
  return mlir::applyOpPatternsGreedily(values, patterns, config);
}

} // namespace talos::detail

#endif // TALOS_LIB_DIALECT_SCHEDULE_TRANSFORMS_KNOWNCASTS_H
