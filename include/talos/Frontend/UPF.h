#ifndef TALOS_FRONTEND_UPF_H
#define TALOS_FRONTEND_UPF_H
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include <memory>
#include <string>
namespace mlir {
class ModuleOp;
class Pass;
} // namespace mlir
namespace talos {
/// Execute UPF against an elaborated Slang IR design. Tcl is compiler-only.
/// Import with FrontendOptions::enableUPF to retain declared selection types.
/// Direct HDL switch expressions are an opt-in extension to 1801-2018 6.22.
mlir::LogicalResult
executeUPF(mlir::ModuleOp module, llvm::ArrayRef<std::string> paths,
           llvm::StringRef resourceDir, llvm::StringRef executablePath,
           bool allowHDLExpressions = false, bool assumePoweredInputs = false);
/// Apply resolved power intent after semantic units have become simulation IR.
std::unique_ptr<mlir::Pass> createElaborateUPFPass();
} // namespace talos
#endif
