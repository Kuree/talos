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
  // IEEE 1801-2018 5.4: sourceWidth identifies the whole HDL object; width
  // and offset describe the selected packed part before context sizing.
  let parameters = (ins EnumParameter<UPFExpressionOpcode>:$opcode,
      OptionalParameter<"::mlir::StringAttr">:$control,
      OptionalParameter<"::mlir::IntegerAttr">:$value,
      OptionalParameter<"::mlir::IntegerAttr">:$unknown,
      DefaultValuedParameter<"bool", "false">:$isSigned,
      DefaultValuedParameter<"bool", "false">:$fill,
      DefaultValuedParameter<"unsigned", "1">:$width,
      DefaultValuedParameter<"unsigned", "1">:$sourceWidth,
      DefaultValuedParameter<"unsigned", "0">:$offset);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFExpressionAttr : UPFAttr<"Expression", "expression"> {
  let summary = "bounded typed postfix UPF Boolean expression (1801-2018 5.4)";
  let parameters = (ins "::mlir::ArrayAttr":$tokens);
  let assemblyFormat = "`<` $tokens `>`";
  let genVerifyDecl = 1;
}
def UPFSwitchStateAttr : UPFAttr<"SwitchState", "state"> {
  let summary = "named abstract power-switch condition (1801-2018 6.22)";
  let parameters = (ins "::mlir::StringAttr":$name, UPFExpressionAttr:$condition);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFSwitchStateArrayAttr
    : TypedArrayAttrBase<UPFSwitchStateAttr, "UPF switch-state array"> {
  let constBuilderCall = "$_builder.getArrayAttr($0)";
}
def UPFSupplyExpressionTokenAttr : UPFAttr<"SupplyExpressionToken", "supply_token"> {
  let summary = "typed supply predicate operand/operator (1801-2018 6.5.4)";
  let parameters = (ins EnumParameter<UPFSupplyExpressionOpcode>:$opcode,
      OptionalParameter<"::mlir::FlatSymbolRefAttr">:$supply,
      OptionalParameter<"::mlir::StringAttr">:$function,
      OptionalParameter<"::mlir::IntegerAttr">:$value,
      OptionalParameter<"::mlir::FloatAttr">:$real);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFSupplyExpressionAttr : UPFAttr<"SupplyExpression", "supply_expression"> {
  let parameters = (ins "::mlir::ArrayAttr":$tokens);
  let assemblyFormat = "`<` $tokens `>`";
  let genVerifyDecl = 1;
}
def UPFPowerStateAttr : UPFAttr<"PowerState", "power_state"> {
  let summary = "deferred supply-set power state (1801-2018 6.5/9.3.2)";
  let parameters = (ins "::mlir::StringAttr":$name,
      OptionalParameter<"::talos::upf::SupplyExpressionAttr">:$condition,
      EnumParameter<UPFSimstate>:$simstate,
      DefaultValuedParameter<"bool", "false">:$illegal);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFPowerStateArrayAttr : TypedArrayAttrBase<UPFPowerStateAttr, "UPF supply power-state array">;
#endif
