//===- SAIF.h - Direct recursive descent SAIF import ---------*- C++ -*-===//

#ifndef TALOS_FRONTEND_SAIF_H
#define TALOS_FRONTEND_SAIF_H

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>

namespace talos::frontend {

struct SAIFResourceLimits {
  uint64_t maxInputBytes = 64 * 1024 * 1024;
  uint64_t maxOperations = 1 << 20;
  unsigned maxNestingDepth = 128;
  unsigned maxConditionTokens = 4096;
};

/// Parse IEEE 1801-2018 Annex I directly into typed saif operations. The
/// parser diagnoses token and grammar errors only. Dialect verification owns
/// header structure, record placement, defaults, and semantic validity. With
/// verifyIR=false, syntactically valid but illegal SAIF remains inspectable IR.
mlir::FailureOr<mlir::OwningOpRef<mlir::ModuleOp>>
importSAIF(llvm::StringRef sourceName, llvm::StringRef contents,
           mlir::MLIRContext &context, bool verifyIR = true,
           const SAIFResourceLimits &limits = {});

} // namespace talos::frontend

#endif // TALOS_FRONTEND_SAIF_H
