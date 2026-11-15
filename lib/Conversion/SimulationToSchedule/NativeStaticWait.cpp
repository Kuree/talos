//===- NativeStaticWait.cpp - Wait records known at compile time ----------===//

#include "NativeStaticWait.h"

#include "talos/Conversion/SimulationRuntime.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace talos::detail {

uint32_t signalWaitFlags(Operation *operation) {
  // An event control has completed before its controlled body runs (9.4.2).
  // Repeating the enclosing always procedure does not keep that wait armed.
  if ((::talos::schedule::has<schedule::metadata::topLevelWildcardWait>(
           operation) ||
       ::talos::schedule::has<schedule::metadata::proceduralEventWait>(
           operation)) &&
      isa<schedule::NativeSuspendChangeOp, schedule::NativeSuspendEdgeOp,
          schedule::NativeSuspendEdgeIffOp, schedule::NativeSuspendAnyOp>(
          operation))
    return TALOS_RT_WAIT_SUPPRESS_ACTIVE_SELF;
  return 0;
}

FailureOr<StaticRuntimeWait> getStaticRuntimeWait(Operation *operation) {
  StaticRuntimeWait result;
  SmallVector<Value> watched;
  TypeSwitch<Operation *>(operation)
      .Case<schedule::NativeSuspendChangeOp>([&](auto op) {
        result.kind = TALOS_RT_SUSPEND_CHANGE;
        watched.push_back(op.getWatched());
        result.edges.push_back(static_cast<uint32_t>(sim::EdgeKind::Change));
      })
      .Case<schedule::NativeSuspendEdgeOp>([&](auto op) {
        result.kind = TALOS_RT_SUSPEND_EDGE;
        watched.push_back(op.getWatched());
        result.edges.push_back(static_cast<uint32_t>(op.getEdge()));
      })
      .Case<schedule::NativeSuspendAnyOp>([&](auto op) {
        result.kind = TALOS_RT_SUSPEND_EDGE;
        llvm::append_range(watched, op.getWatched());
        for (int32_t edge : op.getEdges())
          result.edges.push_back(static_cast<uint32_t>(edge));
      })
      .Default([](Operation *) {});
  auto widths =
      ::talos::schedule::get<::talos::schedule::Field::NativeWaitWidths>(
          operation);
  auto continuation =
      ::talos::schedule::get<::talos::schedule::Field::NativeContinuation>(
          operation);
  auto waitOffset =
      ::talos::schedule::get<::talos::schedule::Field::NativeWaitOffset>(
          operation);
  auto waitSize =
      ::talos::schedule::get<::talos::schedule::Field::NativeWaitSize>(
          operation);
  uint32_t actionFlags = getRuntimeResumeActionFlags(operation);
  if (watched.empty() || watched.size() != result.edges.size() || !widths ||
      static_cast<size_t>(widths.size()) != watched.size() || !continuation ||
      !waitOffset || !waitSize || actionFlags == UINT32_MAX ||
      (actionFlags & TALOS_RT_ACTION_RESUME_POST_OBSERVED) ||
      watched.size() != schedule::getNativeWaitEntryCount(operation))
    return failure();
  for (Value value : watched) {
    APInt handle;
    if (!matchPattern(value, m_ConstantInt(&handle)) ||
        handle.getBitWidth() > 64)
      return failure();
    result.stableIDs.push_back(handle.getZExtValue());
  }
  for (int32_t width : widths.asArrayRef())
    result.widths.push_back(static_cast<uint32_t>(width));
  result.flags = signalWaitFlags(operation);
  result.continuation = static_cast<uint32_t>(continuation.getInt());
  result.actionFlags = TALOS_RT_ACTION_FRAME_WAIT_RECORD | actionFlags;
  result.waitOffset = waitOffset.getInt();
  result.waitSize = waitSize.getInt();
  if (sizeof(talos_rt_wait_record_v1) +
          watched.size() * sizeof(talos_rt_wait_entry_v1) >
      result.waitSize)
    return failure();
  return result;
}

} // namespace talos::detail
