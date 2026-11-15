//===- ActivationPreparation.h - Prepare immutable activation views -*- C++
//-*-===//
#ifndef TALOS_ANALYSIS_ACTIVATIONPREPARATION_H
#define TALOS_ANALYSIS_ACTIVATIONPREPARATION_H

#include "mlir/IR/OwningOpRef.h"
#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace talos::analysis {
class ActivationRegionAnalysis;
class ControlActivationAnalysis;

enum class ActivationFailureReason {
  None,
  ActivationShape,
  InitialResumeEquivalence,
  Termination,
  MemoryEffects,
  UnmappedMemoryAccess,
};

struct ActivationPreparationOptions {
  enum class TracePhase { Initial, Resume };
  enum class ControlFlow { Canonical, ThreadDispatch };
  /// Diagnostic copies only; the callback must not retain their IR.
  using Trace = llvm::function_ref<void(TracePhase, mlir::Operation *)>;
  Trace trace = {};
  ControlFlow controlFlow = ControlFlow::Canonical;
  const ControlActivationAnalysis *controls = nullptr;
  /// The original symbol table for a detached modeled function; otherwise
  /// callees resolve in the function's parent.
  mlir::Operation *symbols = nullptr;
};
using ActivationFrontierTrace =
    llvm::function_ref<void(llvm::StringRef, mlir::Value)>;

/// A closed, normalized activation, ready for read-only memory/region analysis.
/// Preparation owns all rewrites, including loop boundaries. Once returned,
/// its IR must remain unchanged. The source executable IR is never modified.
class PreparedActivation {
public:
  PreparedActivation(PreparedActivation &&) = default;
  PreparedActivation &operator=(PreparedActivation &&) = default;
  bool isValid() const { return reason == ActivationFailureReason::None; }
  ActivationFailureReason getFailureReason() const { return reason; }
  sim::SimFuncOp getFunction() const { return view.get(); }
  /// Symbol table resolving the activation's callees.
  mlir::Operation *getSymbolTable() const {
    return symbols ? symbols : source->getParentOp();
  }

private:
  PreparedActivation() = default;
  friend PreparedActivation
  prepareActivation(sim::SimFuncOp, const ActivationPreparationOptions &);
  friend std::optional<PreparedActivation>
  prepareActivationFrontiers(const ActivationRegionAnalysis &,
                             const HandleDataflowAnalysis &,
                             ActivationFrontierTrace);
  friend class ActivationRegionAnalysis;
  mlir::OwningOpRef<sim::SimFuncOp> view;
  sim::SimFuncOp source;
  mlir::Operation *suspension = nullptr;
  mlir::Operation *symbols = nullptr;
  const ActivationRegionAnalysis *sourceActivation = nullptr;
  ActivationFailureReason reason = ActivationFailureReason::ActivationShape;
};

/// Extract initial/resume copies, apply ordinary dialect canonicalization,
/// check their equivalence and termination, and freeze the resulting view.
PreparedActivation
prepareActivation(sim::SimFuncOp function,
                  const ActivationPreparationOptions &options = {});

/// Prepare a new revision exposing conditional publication boundaries. Saved
/// branch identities and SSA snapshots preserve the source reads. This runs
/// before constructing the refined analysis; it never rewrites an analyzed
/// view. Nullopt means no supported refinement. The source analysis and handle
/// facts must outlive the prepared view and any analysis consuming it.
std::optional<PreparedActivation>
prepareActivationFrontiers(const ActivationRegionAnalysis &activation,
                           const HandleDataflowAnalysis &handles,
                           ActivationFrontierTrace trace = {});
} // namespace talos::analysis
#endif
