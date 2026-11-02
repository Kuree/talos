//===- DPIEffectAnalysis.h - Design state reachable from DPI calls -*- C++
//-*-===//

#ifndef TALOS_ANALYSIS_DPIEFFECTANALYSIS_H
#define TALOS_ANALYSIS_DPIEFFECTANALYSIS_H

namespace talos::sim {
class SimDesignOp;
class SimDPICallOp;
} // namespace talos::sim

namespace talos::analysis {

/// Classifies DPI imports that can affect design state beyond their operands.
/// Non-context imports are local to their value arguments. With VPI off, a
/// context import is transparent only when every export closure touches locals
/// and arguments and has no suspension, process control, scheduler, heap, RNG,
/// or coverage effects. Output and foreign-private effects are allowed.
///
/// `record` freezes the compute graph's export-transparency result on the
/// design so later rewrites can discard summaries without changing the answer.
class DPIEffectAnalysis {
public:
  explicit DPIEffectAnalysis(sim::SimDesignOp design);

  /// Record export transparency on `design` from its current summaries.
  static void record(sim::SimDesignOp design);

  /// Whether `call` may access or control design state through foreign code.
  bool mayAccessDesign(sim::SimDPICallOp call) const;
  /// Whether `call` may do so through an export, ignoring VPI.
  bool mayReachDesignThroughExports(sim::SimDPICallOp call) const;
  /// Whether some DPI call of the design may access design state.
  bool anyCallMayAccessDesign() const { return opaqueCalls; }
  /// Whether every export closure is transparent in the sense above.
  bool exportsAreTransparent() const { return transparentExports; }

private:
  bool transparentExports = false;
  bool transparentContext = false;
  bool opaqueCalls = false;
};

} // namespace talos::analysis

#endif
