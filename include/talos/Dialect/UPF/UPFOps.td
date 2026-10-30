#ifndef TALOS_DIALECT_UPF_OPS_TD
#define TALOS_DIALECT_UPF_OPS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
def UPFDomainOp : Op<UPFDialect, "domain", [Symbol]> {
  let summary = "resolved switchable domain with a single logic-controlled supply";
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$elements,
      StrAttr:$control, BoolAttr:$on_high,
      OptionalAttr<StrAttr>:$isolation_control,
      DefaultValuedAttr<BoolAttr, "true">:$isolation_high,
      DefaultValuedAttr<I64Attr, "0">:$clamp);
  let assemblyFormat = "$sym_name `elements` $elements `control` $control `on_high` `=` $on_high attr-dict";
  let hasVerifier = 1;
}
#endif
