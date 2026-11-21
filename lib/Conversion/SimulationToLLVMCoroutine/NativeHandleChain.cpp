//===- NativeHandleChain.cpp - Stable-handle selection chains -------------===//

#include "NativeHandleChain.h"

#include "talos/Dialect/Schedule/ScheduleOps.h"

using namespace mlir;

namespace talos::detail {

std::optional<NativeHandleOffset> matchNativeHandleOffset(Operation *op) {
  auto offset = dyn_cast_or_null<schedule::NativeHandleOffsetOp>(op);
  if (!offset)
    return std::nullopt;
  return NativeHandleOffset{op, offset.getHandle(), offset.getAmount(),
                            offset.getInBounds()};
}

std::optional<NativeHandleOffset> matchNativeHandleOffset(Value value) {
  return matchNativeHandleOffset(value.getDefiningOp());
}

std::optional<NativeHandleGuard> matchNativeHandleGuard(Operation *op) {
  auto guard = dyn_cast_or_null<schedule::NativeHandleGuardOp>(op);
  if (!guard)
    return std::nullopt;
  return NativeHandleGuard{op, guard.getValid(), guard.getHandle()};
}

std::optional<NativeHandleGuard> matchNativeHandleGuard(Value value) {
  return matchNativeHandleGuard(value.getDefiningOp());
}

NativeHandleChain getNativeHandleChain(Value handle) {
  NativeHandleChain chain{handle, {}};
  while (true) {
    if (std::optional<NativeHandleOffset> offset =
            matchNativeHandleOffset(chain.root)) {
      chain.root = offset->handle;
      chain.links.push_back(*offset);
    } else if (std::optional<NativeHandleGuard> guard =
                   matchNativeHandleGuard(chain.root)) {
      chain.root = guard->handle;
      chain.links.push_back(*guard);
    } else {
      return chain;
    }
  }
}

} // namespace talos::detail
