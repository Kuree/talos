//===- SAIFOps.td - Ordered SAIF exchange records --------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFOPS_TD
#define TALOS_DIALECT_SAIF_SAIFOPS_TD

include "talos/Dialect/SAIF/SAIFAttrs.td"

class SAIFOp<string mnemonic, list<Trait> traits = []>
    : Op<SAIFDialect, mnemonic, traits> {
  let hasVerifier = 1;
}

class SAIFContainer<string mnemonic, list<Trait> traits = []>
    : SAIFOp<mnemonic,
        !listconcat([SingleBlock, NoTerminator, NoRegionArguments], traits)> {
  let regions = (region AnyRegion:$body);
  // Validate children only after their generated ODS invariants have run.
  let hasVerifier = 0;
  let hasRegionVerifier = 1;
}

def SAIF_FileOp : SAIFContainer<"file", [IsolatedFromAbove]> {
  let summary = "one SAIFILE with ordered headers and records";
  let description = [{
    The isolated file is the pass and verification unit for SAIF data.
    Attribute construction checks storage shape; the file verifier caches
    semantic attribute checks and validates document-wide context. Consumers
    that modify a subtree must verify the enclosing file before using it.
  }];
  let arguments = (ins StrAttr:$source);
  let assemblyFormat = "$source attr-dict-with-keyword $body";
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
}

def SAIF_HeaderOp : SAIFOp<"header"> {
  let summary = "one header, retaining ordering, omission, and duplicates";
  let description = [{
    Keeping headers as records lets the verifier check required fields,
    duplicates and ordering, including IR constructed without the importer.
    Empty DIVIDER and TIMESCALE fields are normalized to '.' and 1 ns.
  }];
  let arguments = (ins SAIFHeaderKind:$kind, OptionalAttr<StrAttr>:$text,
      OptionalAttr<StrAttr>:$qualifier, OptionalAttr<SAIFTimeScaleAttr>:$scale,
      OptionalAttr<SAIFNumberAttr>:$value);
  let assemblyFormat = "$kind attr-dict";
}

def SAIF_InstanceOp : SAIFContainer<"instance"> {
  let arguments = (ins SAIFPathAttr:$name, OptionalAttr<StrAttr>:$cell,
      DefaultValuedAttr<BoolAttr, "false">:$is_virtual);
  let assemblyFormat = "qualified($name) attr-dict-with-keyword $body";
}

def SAIF_LibraryOp : SAIFContainer<"library"> {
  let arguments = (ins StrAttr:$name, OptionalAttr<StrAttr>:$directory);
  let assemblyFormat = "$name attr-dict-with-keyword $body";
}

def SAIF_CellOp : SAIFContainer<"cell"> {
  let summary = "library MODULE declaration";
  let arguments = (ins SAIFPathAttr:$name);
  let assemblyFormat = "qualified($name) attr-dict-with-keyword $body";
}

def SAIF_PortsOp : SAIFContainer<"ports"> {
  let assemblyFormat = "attr-dict-with-keyword $body";
}
def SAIF_NetsOp : SAIFContainer<"nets"> {
  let assemblyFormat = "attr-dict-with-keyword $body";
}

def SAIF_SignalOp : SAIFContainer<"signal"> {
  let summary = "backward net or port switching attributes";
  let arguments = (ins SAIFPathAttr:$name);
  let assemblyFormat = "qualified($name) attr-dict-with-keyword $body";
}

def SAIF_PortDirectiveOp : SAIFContainer<"port_directive"> {
  let summary = "library forward pin directives";
  let arguments = (ins SAIFPathAttr:$name);
  let assemblyFormat = "qualified($name) attr-dict-with-keyword $body";
}

def SAIF_MappingOp : SAIFOp<"mapping"> {
  let summary = "RTL forward port or net name mapping";
  let arguments = (ins SAIFPathAttr:$source_name, SAIFPathAttr:$mapped_name,
      OptionalAttr<StrAttr>:$virtual_type);
  let assemblyFormat = [{
    qualified($source_name) `to` qualified($mapped_name) attr-dict
  }];
}

def SAIF_LeakageOp : SAIFContainer<"leakage"> {
  let assemblyFormat = "attr-dict-with-keyword $body";
}

def SAIF_MetricOp : SAIFOp<"metric"> {
  let arguments = (ins SAIFMetricKind:$kind, SAIFNumberAttr:$value);
  let assemblyFormat = "$kind qualified($value) attr-dict";
}

def SAIF_ConditionsOp : SAIFContainer<"conditions"> {
  let summary = "one ordered, priority-encoded COND group";
  let assemblyFormat = "attr-dict-with-keyword $body";
}

def SAIF_WhenOp : SAIFContainer<"when"> {
  let summary = "COND expression or COND_DEFAULT, with optional edge filter";
  let arguments = (ins OptionalAttr<SAIFConditionAttr>:$condition,
      DefaultValuedAttr<SAIFEdge, "::talos::saif::Edge::None">:$edge);
  let assemblyFormat = "(`edge` $edge^)? attr-dict-with-keyword $body";
}

def SAIF_PathsOp : SAIFContainer<"paths"> {
  let summary = "one group of mutually exclusive related-pin lists";
  let assemblyFormat = "attr-dict-with-keyword $body";
}

def SAIF_PathOp : SAIFContainer<"related_pins"> {
  let summary = "IOPATH related pins or IOPATH_DEFAULT";
  let arguments = (ins ArrayAttr:$pins,
      DefaultValuedAttr<BoolAttr, "false">:$is_default);
  let assemblyFormat = "$pins attr-dict-with-keyword $body";
}

#endif // TALOS_DIALECT_SAIF_SAIFOPS_TD
