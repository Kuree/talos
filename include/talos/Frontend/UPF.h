#ifndef TALOS_FRONTEND_UPF_H
#define TALOS_FRONTEND_UPF_H
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include <string>
namespace mlir {
class ModuleOp;
} // namespace mlir
namespace talos {
/// Execute UPF against an elaborated Slang IR design. Tcl is compiler-only.
mlir::LogicalResult executeUPF(mlir::ModuleOp module,
                               llvm::ArrayRef<std::string> paths,
                               llvm::StringRef resourceDir,
                               llvm::StringRef executablePath);
} // namespace talos
#endif
