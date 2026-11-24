//===- NativeRankTrial.h - Native eval ranking -*- C++ -*-===//
#ifndef TALOS_CONVERSION_NATIVE_RANK_TRIAL_H
#define TALOS_CONVERSION_NATIVE_RANK_TRIAL_H
#include "talos/Analysis/NativeEvalRankAnalysis.h"
#include <memory>
namespace mlir {
class Pass;
}
namespace talos::detail {
/// Per-invocation state across native planning and materialization. A trial
/// accepts an order only on the identical graph and rechecks the emitted
/// layout.
struct NativeRankTrial {
  const analysis::NativeRankGraph *expected = nullptr;
  llvm::ArrayRef<uint32_t> selected;
  analysis::NativeRankGraph graph;
  analysis::NativeEvalLayout layout;
  bool encountered = false;
  bool matches = true;
};

std::unique_ptr<mlir::Pass>
createTrialResolveNativeEvalSchedulePass(NativeRankTrial &trial);
} // namespace talos::detail
#endif
