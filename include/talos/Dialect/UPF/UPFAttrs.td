#ifndef TALOS_DIALECT_UPF_ATTRS_TD
#define TALOS_DIALECT_UPF_ATTRS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFEnums.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinAttributes.td"
class UPFAttr<string name, string attrMnemonic> : AttrDef<UPFDialect, name> {
  let mnemonic = attrMnemonic;
}
def UPFPartialOnTranslationAttr : UPFAttr<"PartialOnTranslation", "partial_on_translation"> {
  let summary = "global PARTIAL_ON interpretation (IEEE 1801-2018 6.47)";
  let parameters = (ins EnumParameter<UPFPartialOnTranslation>:$value);
  let assemblyFormat = "`<` $value `>`";
  let genVerifyDecl = 1;
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
def UPFRetentionElementAttr : UPFAttr<"RetentionElement", "retention_element"> {
  let summary = "resolved retention selector with precedence provenance (1801-2018 5.7.3)";
  let parameters = (ins "::mlir::StringAttr":$path,
      EnumParameter<UPFRetentionElementKind>:$kind);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFRetentionTriggerAttr : UPFAttr<"RetentionTrigger", "retention_trigger"> {
  // 6.50: high/low describe an asserted level, with the event at its trailing
  // edge. Preserve that distinction for write priority and event lowering.
  let parameters = (ins UPFExpressionTokenAttr:$control,
      EnumParameter<UPFRetentionTriggerKind>:$kind);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFRetentionAttr : UPFAttr<"Retention", "retention"> {
  let summary = "resolved retention strategy (1801-2018 6.50/9.7)";
  // 8.3.2: combine explicit updates before supplying defaults. domainDefault
  // means no -elements was supplied, including during any -update call.
  let parameters = (ins "::mlir::StringAttr":$name,
      "::mlir::StringAttr":$scope, "::mlir::ArrayAttr":$elements,
      "::mlir::ArrayAttr":$excluded,
      "::mlir::FlatSymbolRefAttr":$retentionSupply,
      "::mlir::FlatSymbolRefAttr":$primarySupply,
      DefaultValuedParameter<"bool", "false">:$domainDefault,
      DefaultValuedParameter<"bool", "false">:$noRetention,
      OptionalParameter<"::talos::upf::RetentionTriggerAttr">:$save,
      OptionalParameter<"::talos::upf::RetentionTriggerAttr">:$restore,
      OptionalParameter<"::talos::upf::ExpressionAttr">:$saveCondition,
      OptionalParameter<"::talos::upf::ExpressionAttr">:$restoreCondition,
      OptionalParameter<"::talos::upf::ExpressionAttr">:$condition,
      OptionalParameter<"::mlir::LocationAttr">:$declaration,
      // 6.50: only the output driver moves to the retention supply. The
      // normal-mode storage input remains powered by the primary supply.
      DefaultValuedParameter<"bool", "false">:$useRetentionAsPrimary);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}
def UPFRetentionArrayAttr
    : TypedArrayAttrBase<UPFRetentionAttr, "UPF retention strategy array"> {
  let constBuilderCall = "$_builder.getArrayAttr($0)";
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
