#ifndef TALOS_DIALECT_UPF_ATTRS_TD
#define TALOS_DIALECT_UPF_ATTRS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFEnums.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinAttributes.td"
class UPFAttr<string name, string attrMnemonic> : AttrDef<UPFDialect, name> {
  let mnemonic = attrMnemonic;
}
def UPFExpressionTokenAttr : UPFAttr<"ExpressionToken", "token"> {
  let summary = "resolved operand or operator in a UPF Boolean expression";
  let parameters = (ins EnumParameter<UPFExpressionOpcode>:$opcode,
      OptionalParameter<"::mlir::StringAttr">:$control,
      OptionalParameter<"::mlir::IntegerAttr">:$value,
      OptionalParameter<"::mlir::IntegerAttr">:$unknown,
      DefaultValuedParameter<"bool", "false">:$isSigned,
      DefaultValuedParameter<"bool", "false">:$fill);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFExpressionAttr : UPFAttr<"Expression", "expression"> {
  let summary = "bounded typed postfix UPF Boolean expression (1801-2018 5.4)";
  let parameters = (ins "::mlir::ArrayAttr":$tokens);
  let assemblyFormat = "`<` $tokens `>`";
  let genVerifyDecl = 1;
}
#endif
