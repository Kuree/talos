//===- SimulationVPIAnalysis.h - VPI capability policy --------*- C++ -*-===//
//
// Read-only analysis of the VPI capabilities recorded in a simulation design.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_ANALYSIS_SIMULATIONVPIANALYSIS_H
#define TALOS_ANALYSIS_SIMULATIONVPIANALYSIS_H

#include "talos/Dialect/Schedule/ScheduleEnums.h"
#include "talos/Dialect/Simulation/SimulationEnums.h"

namespace talos::sim {
class SimDesignOp;
}

namespace talos::analysis {

/// Semantic VPI capabilities for one simulation design.
///
/// Consumers ask capability questions instead of interpreting
/// schedule::ComputeVPIMode themselves. This keeps native lowering, bytecode
/// encoding, and schedule specialization on the same policy.
class SimulationVPIAnalysis {
public:
  static SimulationVPIAnalysis compute(sim::SimDesignOp design);
  static SimulationVPIAnalysis forMode(schedule::ComputeVPIMode mode);

  bool hasComputeGraph() const { return computeGraph; }
  schedule::ComputeVPIMode getMode() const { return mode; }

  schedule::ComputeObservabilityKind getObservability() const;
  bool allowsRead() const;
  bool allowsWrite() const;
  /// Generated owner guards permit a foreign write or an exact read subscriber
  /// to route just the affected state through its publishing executor.
  bool requiresPublicationGuards() const {
    return allowsWrite() || subscriberGuards;
  }

  /// Whether external access preserves the compiler's closed-world dependency
  /// inventory. Read-only observation does; external writes do not.
  bool preservesStaticDependencies() const {
    return computeGraph && !allowsWrite();
  }

private:
  schedule::ComputeVPIMode mode = schedule::ComputeVPIMode::Off;
  bool computeGraph = false;
  bool subscriberGuards = false;
};

/// A variable's continuous driver saves a hidden contribution for procedural
/// assign/force and release (10.6). A closed reader with no such operation
/// can keep its current four-state value alone.
bool needsContinuousContributionHistory(sim::SimDesignOp design);

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_SIMULATIONVPIANALYSIS_H
