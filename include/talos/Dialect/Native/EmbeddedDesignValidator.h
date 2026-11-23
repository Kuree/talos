//===- EmbeddedDesignValidator.h - Compile-time design checks --*- C++ -*-===//

#ifndef TALOS_DIALECT_NATIVE_EMBEDDEDDESIGNVALIDATOR_H
#define TALOS_DIALECT_NATIVE_EMBEDDEDDESIGNVALIDATOR_H

#include "mlir/IR/DialectInterface.h"
#include "mlir/Support/TypeID.h"

struct talos_rt_execution_descriptor_v1;

namespace talos::native {

/// Validates a closed native executable's embedded design database at compile
/// time with the runtime's own loader, so the executable can create its
/// context without validating it again. The compiler libraries do not link
/// the runtime: a driver that builds native executables registers an
/// implementation on the native dialect. Without one, the scheduler main keeps
/// the context creation that validates at run time.
class EmbeddedDesignValidator
    : public mlir::DialectInterface::Base<EmbeddedDesignValidator> {
public:
  explicit EmbeddedDesignValidator(mlir::Dialect *dialect) : Base(dialect) {}

  /// Whether the runtime accepts the design database `descriptor` names.
  virtual bool
  validate(const talos_rt_execution_descriptor_v1 &descriptor) const = 0;
};

} // namespace talos::native

MLIR_DECLARE_EXPLICIT_TYPE_ID(talos::native::EmbeddedDesignValidator)

#endif // TALOS_DIALECT_NATIVE_EMBEDDEDDESIGNVALIDATOR_H
