//===- SDF.h - Static Standard Delay Format annotation --------*- C++ -*-===//
//
// Private frontend support for compiling statically named SDF files into the
// elaborated timing metadata imported into Talos IR.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_LIB_FRONTEND_SDF_H
#define TALOS_LIB_FRONTEND_SDF_H

#include "talos/Frontend/SDF.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace slang {
class SourceManager;
namespace ast {
class CallExpression;
class Compilation;
class SpecparamSymbol;
class Symbol;
class SystemTimingCheckSymbol;
class TimingPathSymbol;
} // namespace ast
} // namespace slang

namespace talos::frontend {

class SDFAnnotationDatabase {
public:
  using DelayVector = llvm::SmallVector<std::optional<int64_t>, 12>;

  struct DelayAnnotation {
    enum class Kind { Absolute, Increment } kind = Kind::Absolute;
    /// PATHPULSEPERCENT: `delays` holds thousandths of a percent of each
    /// transition delay rather than femtoseconds.
    bool percent = false;
    DelayVector delays;
    std::shared_ptr<const std::string> filename;
    unsigned line = 1;
    unsigned column = 1;
  };
  using DelayAnnotations = llvm::SmallVector<DelayAnnotation, 2>;

  const DelayAnnotations *
  getTimingPathAnnotations(const slang::ast::TimingPathSymbol &path) const;
  /// IEEE 1800-2023 32.4.2: `delays` is indexed by timing-check argument
  /// position; an empty entry leaves that limit unchanged.
  const DelayAnnotations *getTimingCheckAnnotations(
      const slang::ast::SystemTimingCheckSymbol &check) const;
  /// IEEE 1800-2023 32.4.3: one value, in femtoseconds, per LABEL entry.
  const DelayAnnotations *
  getSpecparamAnnotations(const slang::ast::SpecparamSymbol &specparam) const;
  bool hasSpecparamAnnotations() const { return !specparamAnnotations.empty(); }
  /// IEEE 1800-2023 30.7.3: `delays` holds the reject and error limits.
  const DelayAnnotations *
  getPathPulseAnnotations(const slang::ast::TimingPathSymbol &path) const;
  /// IEEE 1800-2023 32.4.4: `delays` holds rise, fall, and turn-off delays
  /// of the signal at an annotated input or inout port's internal net.
  const DelayAnnotations *
  getInterconnectAnnotations(const slang::ast::Symbol &portNet) const;
  bool isAppliedCall(const slang::ast::CallExpression &call) const;

private:
  friend std::unique_ptr<SDFAnnotationDatabase>
  buildSDFAnnotationDatabase(slang::ast::Compilation &,
                             const slang::SourceManager &,
                             const SDFResourceLimits &);

  llvm::DenseMap<const slang::ast::TimingPathSymbol *, DelayAnnotations>
      timingPathAnnotations;
  llvm::DenseMap<const slang::ast::SystemTimingCheckSymbol *, DelayAnnotations>
      timingCheckAnnotations;
  llvm::DenseMap<const slang::ast::SpecparamSymbol *, DelayAnnotations>
      specparamAnnotations;
  llvm::DenseMap<const slang::ast::TimingPathSymbol *, DelayAnnotations>
      pathPulseAnnotations;
  llvm::DenseMap<const slang::ast::Symbol *, DelayAnnotations>
      interconnectAnnotations;
  llvm::DenseSet<const slang::ast::CallExpression *> appliedCalls;
};

/// Parse and resolve every statically supported `$sdf_annotate` call in the
/// elaborated design. Returns null after any fatal annotation diagnostic.
std::unique_ptr<SDFAnnotationDatabase>
buildSDFAnnotationDatabase(slang::ast::Compilation &compilation,
                           const slang::SourceManager &sourceManager,
                           const SDFResourceLimits &limits);

} // namespace talos::frontend

#endif // TALOS_LIB_FRONTEND_SDF_H
