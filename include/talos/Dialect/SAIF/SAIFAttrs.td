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

def SAIFTimeScaleAttr : SAIFAttr<"TimeScale", "timescale"> {
  let parameters = (ins SAIFNumberAttr:$amount, "::mlir::StringAttr":$unit);
  let assemblyFormat = "`<` struct(params) `>`";
  let genVerifyDecl = 1;
}

#endif // TALOS_DIALECT_SAIF_SAIFATTRS_TD
