#ifndef TALOS_DIALECT_UPF_DIALECT_TD
#define TALOS_DIALECT_UPF_DIALECT_TD
include "mlir/IR/DialectBase.td"
def UPFDialect : Dialect {
  let name = "upf";
  let cppNamespace = "::talos::upf";
  let summary = "elaborated IEEE 1801 power intent";
  let description = [{
    `upf` represents resolved IEEE 1801 power intent alongside a simulation
    design. Supply declarations identify shared state and voltage roots and
    their absolute handle aliases. Supply sets bind standard supply functions
    to those roots and retain power-state predicates and associations. Domains
    record affected HDL elements, switch conditions, isolation, and retention
    strategies.

    UPF lowering resolves the intent into simulation storage, processes, and
    power-qualified updates, then erases the UPF declarations.
  }];
  let usePropertiesForAttributes = 0;
  let useDefaultAttributePrinterParser = 1;
  let hasOperationAttrVerify = 1;
}
#endif
