#ifndef TALOS_UPF_BOOLEANEXPRESSION_H
#define TALOS_UPF_BOOLEANEXPRESSION_H
#include "talos/Dialect/UPF/UPFAttrs.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/Twine.h"
namespace talos {
mlir::FailureOr<upf::ExpressionAttr> parseUPFBooleanExpression(
    llvm::StringRef text, mlir::MLIRContext *context,
    llvm::function_ref<
        mlir::FailureOr<upf::ExpressionTokenAttr>(llvm::StringRef)>
        resolve,
    llvm::function_ref<void(const llvm::Twine &)> report);
}
#endif
