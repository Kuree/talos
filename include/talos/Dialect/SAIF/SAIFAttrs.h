//===- SAIFAttrs.h - Typed SAIF values -----------------------*- C++ -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFATTRS_H
#define TALOS_DIALECT_SAIF_SAIFATTRS_H

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/SAIF/SAIFEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/SAIF/SAIFAttrs.h.inc"

#endif // TALOS_DIALECT_SAIF_SAIFATTRS_H
