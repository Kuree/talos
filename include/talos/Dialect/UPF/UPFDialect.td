#ifndef TALOS_DIALECT_UPF_DIALECT_TD
#define TALOS_DIALECT_UPF_DIALECT_TD
include "mlir/IR/DialectBase.td"
def UPFDialect : Dialect {
  let name = "upf";
  let cppNamespace = "::talos::upf";
  let summary = "elaborated IEEE 1801 power intent";
  let usePropertiesForAttributes = 0;
  let useDefaultAttributePrinterParser = 1;
}
#endif
