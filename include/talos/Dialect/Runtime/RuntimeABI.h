//===- RuntimeABI.h - Runtime calls and their entries -----------*- C++ -*-===//

#ifndef TALOS_DIALECT_RUNTIME_RUNTIMEABI_H
#define TALOS_DIALECT_RUNTIME_RUNTIMEABI_H

#include "talos/Dialect/Native/NativeRuntimeEntries.h"

#include "llvm/ADT/StringRef.h"

#include <optional>

namespace mlir {
class Operation;
}

namespace talos::runtime {

enum class RuntimeCall {
#define TALOS_RUNTIME_CALL(Name, Op, Entry) Name,
#include "talos/Dialect/Runtime/RuntimeABI.def"
#undef TALOS_RUNTIME_CALL
};

/// The native runtime entry a runtime call calls; its catalog row states the
/// C symbol, the prototype and whether the declaration is cold.
NativeRuntimeEntry getRuntimeEntry(RuntimeCall call);

/// Identify a typed runtime operation, or std::nullopt for another operation.
std::optional<RuntimeCall> getRuntimeCall(mlir::Operation *operation);

} // namespace talos::runtime

#endif // TALOS_DIALECT_RUNTIME_RUNTIMEABI_H
