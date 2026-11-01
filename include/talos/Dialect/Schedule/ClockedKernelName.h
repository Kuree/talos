//===- ClockedKernelName.h - Fused clocked kernel symbols -------*- C++ -*-===//
//
// FuseClockedKernels names every kernel with this prefix. Native clones, eval
// bodies and partition-renamed LLVM functions keep it inside their symbols.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_SCHEDULE_CLOCKEDKERNELNAME_H
#define TALOS_DIALECT_SCHEDULE_CLOCKEDKERNELNAME_H

#include "llvm/ADT/StringRef.h"

namespace talos::schedule {

inline constexpr llvm::StringLiteral clockedKernelPrefix = "__talos_clocked_";

/// Whether a simulation-level symbol belongs to a fused clocked kernel.
inline bool isClockedKernelSymbol(llvm::StringRef symbol) {
  return symbol.starts_with(clockedKernelPrefix);
}

} // namespace talos::schedule

#endif
