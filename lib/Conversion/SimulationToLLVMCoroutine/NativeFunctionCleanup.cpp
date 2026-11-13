//===- NativeFunctionCleanup.cpp - Canonicalize lowered native bodies -----===//
//
// Packed lowering materializes each constant at its use and leaves foldable
// casts, shifts and repeated address computations; on large designs about
// half of its operations fold away. The cleanup of that output belongs where
// it is produced: canonicalizing and CSEing each lowered function here, as a
// function pass MLIR schedules concurrently, lets LLVM conversion and the
// module-wide native finalization steps work on the reduced IR instead of
// only the final LLVM-level cleanup seeing it.
//
//===----------------------------------------------------------------------===//

#include "talos/Conversion/Passes.h"
#include "talos/Dialect/Native/NativeDialect.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/CSE.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_CLEANUPNATIVEFUNCTIONPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
class CleanupNativeFunctionPass final
    : public impl::CleanupNativeFunctionPassBase<CleanupNativeFunctionPass> {
public:
  LogicalResult initialize(MLIRContext *context) override {
    // The canonicalizer's own pattern collection, built once and shared by
    // every function and worker.
    RewritePatternSet owning(context);
    for (Dialect *dialect : context->getLoadedDialects())
      dialect->getCanonicalizationPatterns(owning);
    for (RegisteredOperationName operation : context->getRegisteredOperations())
      operation.getCanonicalizationPatterns(owning, context);
    patterns = std::make_shared<FrozenRewritePatternSet>(std::move(owning));
    return success();
  }

  void runOnOperation() override {
    func::FuncOp function = getOperation();
    // Like the final LLVM cleanup, run only in optimized modules.
    auto module = function->getParentOfType<ModuleOp>();
    auto level =
        module ? native::get<native::OptimizationLevel>(module) : IntegerAttr{};
    if (function.isExternal() || !level || level.getInt() <= 0)
      return markAllAnalysesPreserved();
    // These are ordinary functions, plain processes and eval bodies; none
    // suspends. Suspending processes are already llvm.func coroutine ramps
    // with planned frames, which this func.func pass never visits.
    //
    // The canonicalizer's configuration. Blocks still fold into a single
    // predecessor and branches forward through empty blocks, but identical
    // blocks do not merge: that would turn per-block scratch addresses into
    // block arguments, and lifetime markers must name their allocation.
    // Branch rewrites keep branch weights, and the loads, stores, GEPs and
    // calls that carry native and schedule tags keep them; no later step
    // reads other attributes of a branch. Canonicalization is best-effort,
    // so an unconverged rewrite is no failure.
    GreedyRewriteConfig config;
    config.setUseTopDownTraversal(true).setRegionSimplificationLevel(
        GreedySimplifyRegionLevel::Normal);
    bool changed = false;
    (void)applyPatternsGreedily(function.getOperation(), *patterns, config,
                                &changed);
    // Canonicalization may have erased blocks; build dominance afresh.
    DominanceInfo dominance(function);
    IRRewriter rewriter(&getContext());
    bool eliminated = false;
    eliminateCommonSubExpressions(rewriter, dominance, function, &eliminated);
    if (!changed && !eliminated)
      markAllAnalysesPreserved();
  }

private:
  std::shared_ptr<const FrozenRewritePatternSet> patterns;
};
} // namespace
} // namespace talos
