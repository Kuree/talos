//===- NativeRuntimeCalls.h - Effects of native runtime calls ---*- C++ -*-===//
//
// Effect queries on operations that call native runtime entries; the entries
// and their facts are in talos/Dialect/Native/NativeRuntimeEntries.def.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_RUNTIME_CALLS_H
#define TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_RUNTIME_CALLS_H

#include "talos/Dialect/Native/NativeRuntimeEntries.h"

namespace mlir {
class Operation;
} // namespace mlir

namespace talos::detail {

/// Whether `op` is a native runtime call with `effect`: an LLVM call to an
/// entry, or a typed operation that lowers to calls of entries that all have
/// it. False for another operation.
bool hasNativeRuntimeEffect(mlir::Operation *op, native_runtime::Effect effect);
using ::talos::hasNativeRuntimeEffect;
/// Whether `op` is an LLVM call of `entry`; false for a null `op`.
bool callsNativeRuntime(mlir::Operation *op, NativeRuntimeEntry entry);

} // namespace talos::detail

#endif
