//===- SAIFOps.h - Ordered SAIF records ----------------------*- C++ -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFOPS_H
#define TALOS_DIALECT_SAIF_SAIFOPS_H

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/SAIF/SAIFAttrs.h"
#include "talos/Dialect/SAIF/SAIFDialect.h"

#define GET_OP_CLASSES
#include "talos/Dialect/SAIF/SAIFOps.h.inc"

#endif // TALOS_DIALECT_SAIF_SAIFOPS_H
