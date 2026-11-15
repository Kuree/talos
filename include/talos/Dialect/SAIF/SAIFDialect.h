//===- SAIFDialect.h - SAIF exchange dialect ----------------*- C++ -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFDIALECT_H
#define TALOS_DIALECT_SAIF_SAIFDIALECT_H

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "talos/Dialect/DiscardableAttributes.h"
#include "talos/Dialect/SAIF/SAIFDialect.h.inc"

namespace talos::saif {
using Output = SAIFDialect::OutputAttrHelper;
using Bindings = SAIFDialect::BindingsAttrHelper;
using discardable::get;
using discardable::has;
using discardable::remove;
using discardable::set;
} // namespace talos::saif

#endif // TALOS_DIALECT_SAIF_SAIFDIALECT_H
