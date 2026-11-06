//===- NativeMethodEligibilityAnalysis.h - Method eligibility -*- C++ -*-===//

#ifndef TALOS_ANALYSIS_NATIVEMETHODELIGIBILITYANALYSIS_H
#define TALOS_ANALYSIS_NATIVEMETHODELIGIBILITYANALYSIS_H

#include "mlir/IR/Operation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringMap.h"

#include <cstddef>
#include <cstdint>
#include <utility>

namespace talos::sim {
class SimDesignOp;
class SimFuncOp;
} // namespace talos::sim

namespace talos::analysis {

/// Methods whose complete call closure can use the synchronous native ABI.
/// IEEE 1800-2023 13.3/13.4: a task call is synchronous only if every possible
/// target returns without suspension. Process control, nonlocal exits and
/// foreign calls remain excluded until their native unwind contract is covered.
/// Recursive SCCs propagate exclusions without requiring a topological order.
class NativeMethodEligibilityAnalysis {
public:
  explicit NativeMethodEligibilityAnalysis(sim::SimDesignOp design,
                                           bool includeTasks = true);

  bool canInvoke(sim::SimFuncOp function) const;
  bool canInvoke(llvm::StringRef implementation) const;
  bool canInvokeVirtual(uint64_t signature, bool isTask) const;

  size_t getNumFunctions() const { return functionCount; }
  size_t getNumVirtualFamilies() const { return families.size(); }
  size_t getNumCallEdges() const { return edgeCount; }

private:
  llvm::StringMap<mlir::Operation *> eligible;
  llvm::DenseSet<std::pair<uint64_t, unsigned>> families, ineligibleFamilies;
  size_t functionCount = 0, edgeCount = 0;
};

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_NATIVEMETHODELIGIBILITYANALYSIS_H
