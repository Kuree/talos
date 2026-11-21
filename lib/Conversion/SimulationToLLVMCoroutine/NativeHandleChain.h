//===- NativeHandleChain.h - Stable-handle selection chains -----*- C++ -*-===//
//
// A selection of native state is a chain of stable-handle offsets and
// validity guards above a root handle: `a[i].f` offsets the handle of `a` to
// element `i`, guards the result with the validity of `i`, and offsets that
// to field `f`. An invalid index selects the invalid handle, which names no
// storage (IEEE 1800-2023 7.4.5, 11.5.1, 11.5.2). Native passes read chains
// through these matchers of schedule.handle.offset and schedule.handle.guard,
// which live until AOT planning has read them (lowerNativeHandleOps).
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_HANDLE_CHAIN_H
#define TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_HANDLE_CHAIN_H

#include "mlir/IR/Value.h"

#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>

namespace talos::detail {

/// `handle` offset by `amount` bits.
struct NativeHandleOffset {
  mlir::Operation *op;
  mlir::Value handle;
  mlir::Value amount;
  /// The offset is proved to stay in bounds, so it is the plain sum.
  bool inBounds;
};

/// `handle` where `valid` holds, otherwise the invalid handle.
struct NativeHandleGuard {
  mlir::Operation *op;
  mlir::Value valid;
  mlir::Value handle;
};

std::optional<NativeHandleOffset> matchNativeHandleOffset(mlir::Operation *op);
std::optional<NativeHandleOffset> matchNativeHandleOffset(mlir::Value value);
std::optional<NativeHandleGuard> matchNativeHandleGuard(mlir::Operation *op);
std::optional<NativeHandleGuard> matchNativeHandleGuard(mlir::Value value);

using NativeHandleLink = std::variant<NativeHandleOffset, NativeHandleGuard>;

/// The offsets and guards from a handle down to its root, the first value
/// that is neither; outermost first.
struct NativeHandleChain {
  mlir::Value root;
  llvm::SmallVector<NativeHandleLink, 4> links;
};
NativeHandleChain getNativeHandleChain(mlir::Value handle);

} // namespace talos::detail

#endif // TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_HANDLE_CHAIN_H
