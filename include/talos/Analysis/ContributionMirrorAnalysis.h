//===- ContributionMirrorAnalysis.h - Drivers whose slot equals the net -*-===//

#ifndef TALOS_ANALYSIS_CONTRIBUTIONMIRRORANALYSIS_H
#define TALOS_ANALYSIS_CONTRIBUTIONMIRRORANALYSIS_H

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseSet.h"

#include <cstdint>
#include <optional>

namespace talos::sim {
class SimDesignOp;
}

namespace talos::analysis {

/// A driver descriptor and the bit of its provenance span a driver view
/// starts at.
struct StaticDriverTarget {
  uint64_t id;
  uint64_t lowBit;

  bool operator==(const StaticDriverTarget &other) const {
    return id == other.id && lowBit == other.lowBit;
  }
};

/// The exact driver slice `driver` names: context drivers, descriptor-tagged
/// entry arguments, constant extracts/subelements of them, and block
/// arguments whose every incoming edge names the same slice.
std::optional<StaticDriverTarget>
getExactStaticDriverTarget(mlir::Value driver);

/// The driver descriptor `driver` belongs to, through any view, including
/// dynamically indexed ones.
std::optional<uint64_t> getStaticDriverID(mlir::Value driver);

/// The constant low bit of `driver` within descriptor `driverID`.
std::optional<uint64_t> getStaticDriverOffset(mlir::Value driver,
                                              uint64_t driverID);

/// The driver and low bit a `driver.drive`, `driver.drive_changed` or
/// `driver.drive_delayed_net` updates, as native lowering records them: the
/// frozen schedule fields first, then the exact view, then the descriptor
/// with a constant offset. `exact` is set when the exact view resolved.
struct StaticDriveTarget {
  std::optional<uint64_t> id;
  std::optional<uint64_t> low;
  bool exact = false;
};
StaticDriveTarget getStaticDriveTarget(mlir::Operation *drive,
                                       mlir::Value driver);

/// Drivers whose contribution slot always equals the bits of their net they
/// drive, so the slot never has to be stored. IEEE 1800-2023 6.5: a net's
/// value is the resolution of its drivers; 6.6.1 Table 6-2 and 28.12.1: a
/// lone strong contribution, met only by the z of undriven sources, resolves
/// to its own value on a wire.
///
/// A driver qualifies when its net is an isolated plain wire whose strong
/// drivers do not overlap (IsolatedWireDriverTopology), it is no
/// strength-pair bank (28.6) or user-net driver (6.6.7), and every use of it
/// in the design is a `driver.drive`/`driver.drive_changed` of a constant
/// slice inside its driven range that resolves immediately (no deferred
/// resolution, no raw user-net drive), or a call argument or branch operand
/// forwarding it. Any other use (`driver.read`, the watched handle of a
/// suspension, inertial, delayed-net or NBA drives, an unknown op)
/// disqualifies the driver it names; one whose driver cannot be identified
/// disqualifies every driver. A drive without a constant slice resolves its
/// whole net from every driver's slot, and `net.write` replaces a net's value
/// without its drivers: no driver of such a net qualifies.
///
/// A design with a force, procedural assign or release (10.6.2) has no
/// mirrors: release must restore the value of the drivers, which only the
/// slot holds while the net is forced. Callers must also exclude writable
/// VPI (38.34, 38.35), which can force any net.
llvm::DenseSet<uint64_t>
computeContributionMirrorDrivers(sim::SimDesignOp design);

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_CONTRIBUTIONMIRRORANALYSIS_H
