//===- NativeRuntimeEntries.h - Native runtime entry catalog ----*- C++ -*-===//
//
// The native runtime entries generated code calls: each states its C symbol,
// its prototype and what native passes may assume about a call to it once, in
// NativeRuntimeEntries.def. Lowering declares entries from the catalog, and
// passes query the facts of a call's callee instead of keeping their own lists
// of entry names.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_NATIVE_NATIVERUNTIMEENTRIES_H
#define TALOS_DIALECT_NATIVE_NATIVERUNTIMEENTRIES_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>

namespace mlir {
class FlatSymbolRefAttr;
class Location;
class MLIRContext;
class ModuleOp;
class OpBuilder;
namespace LLVM {
class LLVMFuncOp;
class LLVMFunctionType;
} // namespace LLVM
} // namespace mlir

namespace talos {

enum class NativeRuntimeEntry : uint16_t {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects) Enum,
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
};

/// The prefix the C symbols of the runtime library reserve.
inline constexpr llvm::StringLiteral kRuntimeSymbolPrefix = "talos_rt_";

namespace native_runtime {
/// A parameter or result type of an entry's prototype, as declared to LLVM:
/// the tokens of a row's SIG.
enum Type : uint8_t { V, I1, I8, I16, I32, I64, F32, F64, Ptr };

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
constexpr llvm::StringLiteral getNativeRuntimeSymbol(NativeRuntimeEntry entry) {
  switch (entry) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  case NativeRuntimeEntry::Enum:                                               \
    return #symbol;
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
  }
  return "";
}
/// The facts of `entry`.
uint32_t getNativeRuntimeEffects(NativeRuntimeEntry entry);
/// Whether every call to `callee` has `effect`; false for another callee.
bool hasNativeRuntimeEffect(llvm::StringRef callee,
                            native_runtime::Effect effect);
/// The result type of `entry`, then its parameter types.
llvm::ArrayRef<native_runtime::Type>
getNativeRuntimeSignature(NativeRuntimeEntry entry);
/// A reference to the symbol of `entry`, as a call's callee.
mlir::FlatSymbolRefAttr getNativeRuntimeCallee(mlir::MLIRContext *context,
                                               NativeRuntimeEntry entry);
/// The LLVM function type of `entry`.
mlir::LLVM::LLVMFunctionType
getNativeRuntimeFunctionType(mlir::MLIRContext *context,
                             NativeRuntimeEntry entry);
/// A new external declaration of `entry` at the insertion point of `builder`,
/// with the entry's prototype, its `native.runtime_entry` attribute and, for a
/// Cold entry, the `cold` attribute.
mlir::LLVM::LLVMFuncOp createNativeRuntimeDeclaration(mlir::OpBuilder &builder,
                                                      mlir::Location location,
                                                      NativeRuntimeEntry entry);
/// The declaration of `entry` in `module`: the existing one, or a new one
/// (createNativeRuntimeDeclaration) at the start of the module. An existing
/// declaration of another type is reported as an error on it.
mlir::LLVM::LLVMFuncOp declareNativeRuntime(mlir::ModuleOp module,
                                            NativeRuntimeEntry entry);
/// Declares each of `entries` in order (declareNativeRuntime).
void declareNativeRuntimes(mlir::ModuleOp module,
                           llvm::ArrayRef<NativeRuntimeEntry> entries);

} // namespace talos

#endif
