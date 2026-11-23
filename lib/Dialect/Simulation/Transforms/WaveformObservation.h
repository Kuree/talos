//===- WaveformObservation.h - Waveform observations of pending copies ----===//

#ifndef TALOS_LIB_DIALECT_SIMULATION_TRANSFORMS_WAVEFORMOBSERVATION_H
#define TALOS_LIB_DIALECT_SIMULATION_TRANSFORMS_WAVEFORMOBSERVATION_H

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Dialect/Simulation/SimulationOps.h"

namespace talos::sim {

/// A dump checkpoint normally observes the current activation. At the start
/// of a new Active activation its previous writes and their continuous copies
/// are settled. Other Active processes may legally run on either side of
/// that activation (IEEE 1800-2023 4.5, 4.7, 21.7.1.4).
inline bool dumpCanObservePendingCopy(mlir::Operation *op) {
  if (!mlir::isa<SimDumpAllOp, SimDumpControlOp>(op))
    return false;
  auto function = op->getParentOfType<SimFuncOp>();
  if (!function || function.getHomeRegion() != EventRegion::Active)
    return true;
  mlir::Block *block = op->getBlock();
  mlir::Block *pred = block->getSinglePredecessor();
  auto delay = pred ? mlir::dyn_cast<SimSuspendDelayOp>(pred->getTerminator())
                    : SimSuspendDelayOp{};
  auto ticks = delay ? delay.getDelay().getDefiningOp<SimTimeConstantOp>()
                     : SimTimeConstantOp{};
  if (!ticks || !ticks.getValue())
    return true;
  for (mlir::Operation &prior :
       llvm::make_range(block->begin(), op->getIterator()))
    if (!mlir::isMemoryEffectFree(&prior))
      return true;
  return false;
}

} // namespace talos::sim

#endif
