#ifndef TALOS_UPF_CONTROLREFERENCE_H
#define TALOS_UPF_CONTROLREFERENCE_H
#include "talos/Dialect/UPF/UPFAttrs.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Twine.h"

namespace talos {
// A resolved HDL object or static packed selection (1801-2018 5.3.3.2/5.4).
// Preserve source indices until aliases and any subsequent selectors resolve.
struct ControlReference {
  std::string path;
  mlir::ArrayAttr types;
  mlir::DenseBoolArrayAttr signs;
  unsigned stage = 0;
  unsigned width = 1, sourceWidth = 1, offset = 0;
  bool isSigned = false;
  static mlir::FailureOr<ControlReference>
  create(llvm::StringRef path, mlir::Type type, mlir::ArrayAttr types,
         mlir::DenseBoolArrayAttr signs,
         llvm::function_ref<void(const llvm::Twine &)> report);
  mlir::LogicalResult
  select(llvm::StringRef selectors,
         llvm::function_ref<void(const llvm::Twine &)> report);
  upf::ExpressionTokenAttr token(mlir::MLIRContext *context) const;
};
} // namespace talos
#endif
