#ifndef TALOS_DIALECT_UPF_OPS_TD
#define TALOS_DIALECT_UPF_OPS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFAttrs.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
def UPFSupplyOp : Op<UPFDialect, "supply", [Symbol]> {
  let summary = "one shared root supply value and its absolute handle aliases";
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$names,
      BoolAttr:$writable, DefaultValuedAttr<I64Attr, "0">:$initial_value);
  let assemblyFormat = "$sym_name `names` $names `writable` `=` $writable attr-dict";
  let hasVerifier = 1;
}
def UPFSupplySetOp : Op<UPFDialect, "supply_set", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "supply-set identity with resolved function roots and requirements";
  let arguments = (ins SymbolNameAttr:$sym_name, DictionaryAttr:$functions,
      StrArrayAttr:$required, OptionalAttr<UPFPowerStateArrayAttr>:$states,
      OptionalAttr<FlatSymbolRefArrayAttr>:$associated,
      OptionalAttr<FlatSymbolRefAttr>:$owner,
      DefaultValuedAttr<BoolAttr, "false">:$complete);
  let assemblyFormat = "$sym_name `functions` $functions `required` $required attr-dict";
  let hasVerifier = 1;
}
def UPFDomainOp : Op<UPFDialect, "domain", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "resolved power domain with supply roots and optional switch";
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$elements,
      FlatSymbolRefAttr:$power, OptionalAttr<FlatSymbolRefAttr>:$ground,
      OptionalAttr<FlatSymbolRefAttr>:$input,
      OptionalAttr<FlatSymbolRefAttr>:$primary,
      OptionalAttr<FlatSymbolRefArrayAttr>:$policies,
      UPFSwitchStateArrayAttr:$on, OptionalAttr<UPFSwitchStateAttr>:$off,
      OptionalAttr<UPFSwitchStateArrayAttr>:$errors,
      OptionalAttr<StrAttr>:$isolation_control,
      DefaultValuedAttr<BoolAttr, "true">:$isolation_high,
      DefaultValuedAttr<I64Attr, "0">:$clamp);
  let assemblyFormat = "$sym_name `elements` $elements `power` $power `on` $on attr-dict";
  let hasVerifier = 1;
}
#endif
