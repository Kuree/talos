//===- PrepareSAIFLibrary.h - Bind library characterization directives ----===//
#ifndef TALOS_CONVERSION_PREPARESAIFLIBRARY_H
#define TALOS_CONVERSION_PREPARESAIFLIBRARY_H
#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/SAIF/SAIFOps.h"
#include "llvm/ADT/DenseMap.h"
namespace talos {
mlir::FailureOr<mlir::ArrayAttr>
prepareSAIFLibrary(mlir::ModuleOp module, mlir::ArrayRef<saif::FileOp> files,
                   const llvm::DenseMap<uint64_t, saif::PathAttr> &scopePaths,
                   mlir::ArrayRef<mlir::Attribute> bindings,
                   mlir::ArrayRef<uint8_t> outputs);
}
#endif
