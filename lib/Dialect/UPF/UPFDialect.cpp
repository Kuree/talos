#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/UPF/UPFOps.h"

#include "talos/Dialect/UPF/UPFDialect.cpp.inc"
#define GET_OP_CLASSES
#include "talos/Dialect/UPF/UPFOps.cpp.inc"
namespace talos::upf {
void UPFDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "talos/Dialect/UPF/UPFOps.cpp.inc"
      >();
}
mlir::LogicalResult UPFDomainOp::verify() {
  if (getElements().empty() || getControl().empty())
    return emitOpError("requires domain elements and a power control");
  for (auto element : getElements())
    if (mlir::cast<mlir::StringAttr>(element).getValue().empty())
      return emitOpError("domain element must not be empty");
  if (auto isolation = getIsolationControl(); isolation && isolation->empty())
    return emitOpError("isolation control must not be empty");
  if (getClamp() != 0 && getClamp() != 1)
    return emitOpError("isolation clamp must be zero or one");
  return mlir::success();
}
} // namespace talos::upf
