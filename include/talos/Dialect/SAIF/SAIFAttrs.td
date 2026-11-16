//===- SAIFAttrs.td - Typed SAIF values ------------------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFATTRS_TD
#define TALOS_DIALECT_SAIF_SAIFATTRS_TD

include "talos/Dialect/SAIF/SAIFDialect.td"
include "talos/Dialect/SAIF/SAIFEnums.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinAttributes.td"

class SAIFAttr<string name, string mnemonic_> : AttrDef<SAIFDialect, name> {
  let mnemonic = mnemonic_;
  // Construction checks only required storage parameters. Semantically
  // illegal source values remain representable; the owning file verifies
  // distinct immutable values once, including their element structure.
}

def SAIFNumberAttr : SAIFAttr<"Number", "number"> {
  let summary = "nonnegative finite binary64 number, retaining its spelling";
  let parameters = (ins "::mlir::StringAttr":$spelling);
  let assemblyFormat = "`<` $spelling `>`";
  let genVerifyDecl = 1;
}

def SAIFIdentifierAttr : SAIFAttr<"Identifier", "identifier"> {
  let summary = "decoded identifier and optional decimal bit index";
  let description = [{
    Character escapes are decoded in `name`. A literal escaped bracket in
    that name is distinct from a bit select in `index`. Indices have canonical
    unsigned decimal spelling, without leading zeroes except for zero itself.
  }];
  let parameters = (ins "::mlir::StringAttr":$name,
      OptionalParameter<"::mlir::StringAttr">:$index);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

def SAIFPathAttr : SAIFAttr<"Path", "path"> {
  let summary = "hierarchical name with explicit identifier components";
  let parameters = (ins "::mlir::ArrayAttr":$components);
  let assemblyFormat = "`<` $components `>`";
  let genVerifyDecl = 1;
}

def SAIFConditionTokenAttr : SAIFAttr<"ConditionToken", "condition_token"> {
  let parameters = (ins EnumParameter<SAIFConditionOpcode>:$opcode,
      OptionalParameter<"::talos::saif::IdentifierAttr">:$pin);
  let assemblyFormat = "`<` struct(params) `>`";
}

def SAIFConditionAttr : SAIFAttr<"Condition", "condition"> {
  let summary = "postfix condition; precedence is !, *, ^, |";
  let parameters = (ins "::mlir::ArrayAttr":$tokens);
  let assemblyFormat = "`<` $tokens `>`";
  let genVerifyDecl = 1;
}

// A prepared, per-bit observation. Numeric source descriptors survive name
// pruning; structured output names survive escaped source identifiers.
def SAIFBindingAttr : SAIFAttr<"Binding", "binding"> {
  let parameters = (ins "uint64_t":$sourceId, "bool":$sourceIsNet,
      "uint64_t":$sourceLow, SAIFPathAttr:$instance,
      SAIFIdentifierAttr:$signal, "bool":$port, "uint32_t":$initial,
      OptionalParameter<"::mlir::StringAttr">:$virtualType);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

def SAIFPinBindingAttr : SAIFAttr<"PinBinding", "pin_binding"> {
  let parameters = (ins SAIFIdentifierAttr:$name, "uint64_t":$observation,
      "bool":$output);
  let assemblyFormat = "`<` struct(params) `>`";
}
def SAIFRelatedAttr : SAIFAttr<"Related", "related"> {
  let parameters = (ins "::mlir::ArrayAttr":$pins, "bool":$isDefault);
  let assemblyFormat = "`<` struct(params) `>`";
}
def SAIFRuleAttr : SAIFAttr<"Rule", "rule"> {
  let parameters = (ins OptionalParameter<"::talos::saif::ConditionAttr">:$condition,
      "bool":$splitEdges, "::mlir::ArrayAttr":$paths);
  let assemblyFormat = "`<` struct(params) `>`";
}
def SAIFGroupAttr : SAIFAttr<"Group", "group"> {
  let parameters = (ins "uint64_t":$observation, "bool":$leakage,
      "bool":$conditional, "::mlir::ArrayAttr":$rules);
  let assemblyFormat = "`<` struct(params) `>`";
}
def SAIFCellBindingAttr : SAIFAttr<"CellBinding", "cell_binding"> {
  let parameters = (ins SAIFPathAttr:$instance, "::mlir::StringAttr":$cell,
      "::mlir::ArrayAttr":$pins, "::mlir::ArrayAttr":$groups);
  let assemblyFormat = "`<` struct(params) `>`";
}

def SAIFTimeScaleAttr : SAIFAttr<"TimeScale", "timescale"> {
  let parameters = (ins SAIFNumberAttr:$amount, "::mlir::StringAttr":$unit);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

#endif // TALOS_DIALECT_SAIF_SAIFATTRS_TD
