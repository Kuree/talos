//===- NativeStaticWait.h - Wait records known at compile time -*- C++ -*-===//
//
// A change, edge or any wait whose watched handles are constants has a
// runtime wait record and resume action known at compile time. Admission of
// owners created at their wait and emission of their start records share
// this one description, so a wait is admitted exactly when it can be emitted.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_LIB_CONVERSION_SIMULATIONTOSCHEDULE_NATIVESTATICWAIT_H
#define TALOS_LIB_CONVERSION_SIMULATIONTOSCHEDULE_NATIVESTATICWAIT_H

#include "mlir/IR/Operation.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace talos::detail {

/// The wait-record flag bits that depend only on how a signal wait was
/// written (TALOS_RT_WAIT_SUPPRESS_ACTIVE_SELF). serializeRuntimeWait adds
/// the kind-specific bits of other waits.
uint32_t signalWaitFlags(mlir::Operation *operation);

/// The runtime wait record (talos_rt_wait_record_v1 and its entries) and
/// resume action that the suspension lowering would publish for a change,
/// edge or any wait whose watched handles are constants.
struct StaticRuntimeWait {
  uint32_t kind = 0;
  uint32_t flags = 0;
  uint32_t continuation = 0;
  uint32_t actionFlags = 0;
  uint64_t waitOffset = 0;
  uint64_t waitSize = 0;
  llvm::SmallVector<uint64_t, 4> stableIDs;
  llvm::SmallVector<uint32_t, 4> edges;
  llvm::SmallVector<uint32_t, 4> widths;
};

/// The static record of `operation`, or failure when it is not such a wait,
/// a watched handle is not constant, or the frame's wait field cannot hold it.
mlir::FailureOr<StaticRuntimeWait>
getStaticRuntimeWait(mlir::Operation *operation);

} // namespace talos::detail
#endif
