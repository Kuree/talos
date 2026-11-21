//===- NativeHandleChain.cpp - Stable-handle selection chains -------------===//

#include "NativeHandleChain.h"

#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace talos::detail {
namespace {
bool isInvalidHandle(Value value) {
  IntegerAttr constant;
  return matchPattern(value, m_Constant(&constant)) &&
         constant.getType().isInteger(64) && constant.getValue().isAllOnes();
}
} // namespace

std::optional<NativeHandleOffset> matchNativeHandleOffset(Operation *op) {
  if (auto offset = dyn_cast_or_null<schedule::NativeHandleOffsetOp>(op))
    return NativeHandleOffset{op, offset.getHandle(), offset.getAmount(),
                              offset.getInBounds()};
  auto call = dyn_cast_or_null<LLVM::CallOp>(op);
  if (!call || call.getCallee() != "talos_rt_v1_native_handle_offset" ||
      call.getArgOperands().size() != 2)
    return std::nullopt;
  return NativeHandleOffset{op, call.getArgOperands()[0],
                            call.getArgOperands()[1],
                            native::has<native::InBoundsHandleOffset>(call)};
}

std::optional<NativeHandleOffset> matchNativeHandleOffset(Value value) {
  return matchNativeHandleOffset(value.getDefiningOp());
}

std::optional<NativeHandleGuard> matchNativeHandleGuard(Operation *op) {
  if (auto guard = dyn_cast_or_null<schedule::NativeHandleGuardOp>(op))
    return NativeHandleGuard{op, guard.getValid(), guard.getHandle(),
                             /*inverted=*/false};
  if (!isa_and_nonnull<arith::SelectOp, LLVM::SelectOp>(op))
    return std::nullopt;
  Value valid = op->getOperand(0);
  if (isInvalidHandle(op->getOperand(2)))
    return NativeHandleGuard{op, valid, op->getOperand(1), /*inverted=*/false};
  if (isInvalidHandle(op->getOperand(1)))
    return NativeHandleGuard{op, valid, op->getOperand(2), /*inverted=*/true};
  return std::nullopt;
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
