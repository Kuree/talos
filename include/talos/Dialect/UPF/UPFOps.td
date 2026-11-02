#ifndef TALOS_DIALECT_UPF_OPS_TD
#define TALOS_DIALECT_UPF_OPS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFAttrs.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
def UPFSupplyOp : Op<UPFDialect, "supply", [Symbol]> {
  let summary = "one shared root supply value and its absolute handle aliases";
  let description = [{
    Declares one supply root shared by all entries in `names`, which must be
    unique absolute handle names. `initial_value` packs the supply state into
    bits 1:0 and signed 32-bit microvolts into bits 33:2. `writable` identifies
    externally controlled roots. An `always_on` root is protected from writes
    and starts FULL_ON.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$names,
      BoolAttr:$writable, DefaultValuedAttr<I64Attr, "0">:$initial_value,
      DefaultValuedAttr<BoolAttr, "false">:$always_on);
  let assemblyFormat = "$sym_name `names` $names `writable` `=` $writable attr-dict";
  let hasVerifier = 1;
}
def UPFSupplySetOp : Op<UPFDialect, "supply_set", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "supply-set identity with resolved function roots and requirements";
  let description = [{
    Maps all six standard supply functions to `upf.supply` roots. `required`
    records the subset used by the resolved intent. Associated sets retain
    distinct identities while sharing corresponding function roots and
    required functions, with reciprocal association links.

    Optional power states retain typed predicates and simulation states.
    Strategy-local handles also identify their owning domain and strategy;
    a binding names an associated supplier.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, DictionaryAttr:$functions,
      StrArrayAttr:$required, OptionalAttr<UPFPowerStateArrayAttr>:$states,
      OptionalAttr<FlatSymbolRefArrayAttr>:$associated,
      OptionalAttr<FlatSymbolRefAttr>:$owner,
      DefaultValuedAttr<BoolAttr, "false">:$complete,
      OptionalAttr<StrAttr>:$strategy,
      OptionalAttr<FlatSymbolRefAttr>:$binding);
  let assemblyFormat = "$sym_name `functions` $functions `required` $required attr-dict";
  let hasVerifier = 1;
}
def UPFDomainOp : Op<UPFDialect, "domain", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "resolved power domain with supply roots and optional switch";
  let description = [{
    Identifies the HDL elements governed by a power domain and its resolved
    power, ground, input, and primary supply bindings. Named switch conditions
    distinguish on, partial, off, and error states. Isolation attributes retain
    the control polarity, clamp value, and supply-comparison policy; retention
    attributes retain resolved selectors, control events, and strategy supply
    handles for UPF lowering.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$elements,
      FlatSymbolRefAttr:$power, OptionalAttr<FlatSymbolRefAttr>:$ground,
      OptionalAttr<FlatSymbolRefAttr>:$input,
      OptionalAttr<FlatSymbolRefAttr>:$primary,
      OptionalAttr<FlatSymbolRefArrayAttr>:$policies,
      UPFSwitchStateArrayAttr:$on, OptionalAttr<UPFSwitchStateArrayAttr>:$partial,
      OptionalAttr<UPFSwitchStateAttr>:$off,
      OptionalAttr<UPFSwitchStateArrayAttr>:$errors,
      OptionalAttr<StrAttr>:$isolation_control,
      DefaultValuedAttr<BoolAttr, "true">:$isolation_high,
      DefaultValuedAttr<I64Attr, "0">:$clamp,
      OptionalAttr<UPFRetentionArrayAttr>:$retentions,
      OptionalAttr<StrAttr>:$isolation_name,
      // IEEE 1801 6.45: omitted/bare is TRUE; FALSE removes only the
      // driver/receiver supply comparison from isolation's port filters.
      DefaultValuedAttr<BoolAttr, "true">:$isolation_diff_supply_only);
  let assemblyFormat = "$sym_name `elements` $elements `power` $power `on` $on attr-dict";
  let hasVerifier = 1;
}
#endif
