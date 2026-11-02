//===- SteadyUnknownAnalysis.h - Steady-state X/Z patterns -*- C++ -*- ===//
//
// Finds candidate X/Z bits in design storage: bits left at an X/Z declaration
// default and bits that repeating writes only fill with X/Z.
//
// A sparse value analysis and root/private-storage states solve the least
// fixed point of bits that may become known. Unmodeled computations and reads
// may be known; an unattributed write invalidates the whole result. Initial
// values and run-once writes matter unless repeating writes completely cover
// the affected bits. Bounded-loop indices refine indexed writes.
//
// Packed values and nested arrays are tracked per bit within the analysis's
// size limit; larger shapes share a mask across packed leaves.
//
// These patterns require runtime validation. Startup writes can leave a bit
// known, and external writes can change it. Clients must check the actual
// unknown plane before specializing accesses.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_ANALYSIS_STEADYUNKNOWNANALYSIS_H
#define TALOS_ANALYSIS_STEADYUNKNOWNANALYSIS_H

#include "mlir/Support/LLVM.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

namespace talos::sim {
class SimDesignOp;
}

namespace talos::analysis {

class SteadyUnknownAnalysis {
public:
  /// Sorted, disjoint (offset, width) ranges relative to a root.
  using Ranges = llvm::SmallVector<std::pair<uint64_t, uint64_t>, 2>;

  /// Fails only on malformed IR.
  static mlir::FailureOr<SteadyUnknownAnalysis>
  compute(sim::SimDesignOp design);

  /// The bits of root `descriptor` that hold X/Z in steady state.
  llvm::ArrayRef<std::pair<uint64_t, uint64_t>>
  lookup(uint64_t descriptor) const {
    auto found = roots.find(descriptor);
    return found == roots.end()
               ? llvm::ArrayRef<std::pair<uint64_t, uint64_t>>()
               : llvm::ArrayRef(found->second);
  }
  /// Roots with at least one such bit.
  const llvm::DenseMap<uint64_t, Ranges> &getRoots() const { return roots; }
  /// A write could not be attributed, so no bit is known to hold X/Z.
  bool isTop() const { return top; }

private:
  llvm::DenseMap<uint64_t, Ranges> roots;
  bool top = false;
};

} // namespace talos::analysis

#endif // TALOS_ANALYSIS_STEADYUNKNOWNANALYSIS_H
