//===- NativeRuntimeEntries.h - Native runtime entry effects ----*- C++ -*-===//
//
// What native passes may assume about a call to a native runtime entry. Each
// entry states its facts once, in NativeRuntimeEntries.def; passes query the
// facts of a call's callee instead of keeping their own lists of entry names.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_RUNTIME_ENTRIES_H
#define TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_RUNTIME_ENTRIES_H

#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>

namespace mlir {
class Operation;
} // namespace mlir

namespace talos::detail {

enum class NativeRuntimeEntry : uint16_t {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, effects) Enum,
#include "NativeRuntimeEntries.def"
};

namespace native_runtime {
/// Facts about every call to an entry, whatever its arguments.
enum Effect : uint32_t {
  None = 0,
  /// Executes no actor, does not suspend and does not advance time: a
  /// generated eval activation keeps the call inline.
  EvalInline = 1u << 0,
  /// Cannot read, stage or consume a pending NBA capture.
  PendingTransparent = 1u << 1,
  /// Cannot read or change a ready set.
  ReadinessTransparent = 1u << 2,
  /// Cannot publish to a runtime actor between two NBA cuts of the eval
  /// coordinator.
  CutQuiet = 1u << 3,
  /// Cannot change the generic NBA queue's binding or add another writer
  /// between two of its captures.
  QueueStable = 1u << 4,
  /// Updates at most the generic NBA queue and its membership words, never
  /// which bitmap describes the queue.
  QueueCaptureOnly = 1u << 5,
  /// Reached only from a cold path, such as a failed capacity test.
  Cold = 1u << 6,
};
} // namespace native_runtime

/// The entry `callee` names, if it is one.
std::optional<NativeRuntimeEntry> getNativeRuntimeEntry(llvm::StringRef callee);
/// The C symbol of `entry`.
llvm::StringRef getNativeRuntimeSymbol(NativeRuntimeEntry entry);
/// The facts of `entry`.
uint32_t getNativeRuntimeEffects(NativeRuntimeEntry entry);
/// Whether every call to `callee` has `effect`; false for another callee.
bool hasNativeRuntimeEffect(llvm::StringRef callee,
                            native_runtime::Effect effect);
/// Whether `op` is a native runtime call with `effect`: an LLVM call to an
/// entry, or a typed operation that lowers to calls of entries that all have
/// it. False for another operation.
bool hasNativeRuntimeEffect(mlir::Operation *op, native_runtime::Effect effect);

} // namespace talos::detail

#endif
