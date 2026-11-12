//===- Passes.h - Dialect-independent optimization passes ------*- C++ -*-===//

#ifndef TALOS_TRANSFORMS_PASSES_H
#define TALOS_TRANSFORMS_PASSES_H

#include "mlir/Pass/Pass.h"

namespace talos {

#define GEN_PASS_DECL
#include "talos/Transforms/Passes.h.inc"

#define GEN_PASS_REGISTRATION
#include "talos/Transforms/Passes.h.inc"

} // namespace talos

#endif // TALOS_TRANSFORMS_PASSES_H
