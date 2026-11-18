//===- FallbackReport.h - Structured tier-1 fallback records ---*- C++ -*-===//
//
// Every decision that keeps code off the tier-1 path (a runtime checkpoint, a
// tier-2 convergence executor, a design-wide eval mode, a rejected cohort)
// can explain itself as one record. Records are opt-in: the native
// `fallback_report` module marker enables them. The driver routes them to a
// file as JSON lines; otherwise each goes to stderr as "talos fallback: "
// followed by the JSON object.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_NATIVE_FALLBACKREPORT_H
#define TALOS_DIALECT_NATIVE_FALLBACKREPORT_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"
#include <optional>
#include <string>

namespace talos::native {

/// One decision that keeps code off the tier-1 path.
struct FallbackRecord {
  /// What was demoted: "checkpoint", "tier2", "eval-disabled",
  /// "aot-disabled" or "cohort-rejected".
  llvm::StringRef kind;
  /// Stable, machine-readable reason, e.g. "runtime-state-access".
  llvm::StringRef reason;
  /// The demoted executor's function, when there is one.
  llvm::StringRef owner;
  /// Where the demoted code comes from.
  std::optional<mlir::Location> location;
  /// The operation that caused the demotion, when known.
  std::optional<mlir::Location> blocker;
  /// Free-form context (operation name, member count, ...).
  std::string detail;
};

/// Whether `module` asks for fallback records.
bool isFallbackReportEnabled(mlir::ModuleOp module);

/// Emit `record` when `module` asks for fallback records. Thread-safe.
void reportFallback(mlir::ModuleOp module, const FallbackRecord &record);

/// Route records to `stream` (stderr when null). The driver owns the stream
/// and must reset this before destroying it.
void setFallbackReportStream(llvm::raw_ostream *stream);

} // namespace talos::native

#endif // TALOS_DIALECT_NATIVE_FALLBACKREPORT_H
