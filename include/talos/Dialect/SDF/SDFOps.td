//===- SDFOps.td - Transient normalized SDF operations ------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SDF_SDFOPS_TD
#define TALOS_DIALECT_SDF_SDFOPS_TD

include "talos/Dialect/SDF/SDFAttrs.td"
include "mlir/IR/BuiltinAttributes.td"

class SDFOp<string mnemonic, list<Trait> traits = []>
    : Op<TalosSDFDialect, mnemonic, traits>;

def SDFDelayFileOp : SDFOp<"delay_file", [
    IsolatedFromAbove, SingleBlock, NoTerminator
  ]> {
  let summary = "one normalized IEEE 1800 Clause 32 delay file";
  let description = [{
    Owns the source path, SDF version, optional header metadata, and an ordered
    body of `sdf.cell` operations. The file is nested directly in a module.
    Decimal delay values and the optional timescale remain separate until
    frontend annotation resolves them against the elaborated design.
  }];
  let arguments = (ins StrAttr:$source, StrAttr:$sdf_version,
      OptionalAttr<StrAttr>:$design, OptionalAttr<StrAttr>:$date,
      OptionalAttr<StrAttr>:$vendor, OptionalAttr<StrAttr>:$program,
      OptionalAttr<StrAttr>:$program_version,
      OptionalAttr<StrAttr>:$divider, OptionalAttr<SDFDelayValueAttr>:$voltage,
      OptionalAttr<StrAttr>:$process,
      OptionalAttr<SDFDelayValueAttr>:$temperature,
      OptionalAttr<SDFTimeScaleAttr>:$timescale);
  let regions = (region AnyRegion:$body);
  let assemblyFormat = "$source `version` $sdf_version attr-dict-with-keyword $body";
  let hasVerifier = 1;
}

def SDFCellOp : SDFOp<"cell", [SingleBlock, NoTerminator,
    HasParent<"SDFDelayFileOp">]> {
  let summary = "one CELL and its ordered annotation records";
  let description = [{
    Selects a cell type and either a named instance or wildcard instances.
    Its body contains only SDF annotation operations, in source order, so
    absolute and incremental annotations retain their application order.
  }];
  let arguments = (ins StrAttr:$cell_type, OptionalAttr<StrAttr>:$instance,
      OptionalAttr<UnitAttr>:$wildcard);
  let regions = (region AnyRegion:$body);
  let assemblyFormat = [{
    $cell_type (`instance` $instance^)? (`wildcard` $wildcard^)?
    attr-dict-with-keyword $body
  }];
  let hasVerifier = 1;
}

def SDFPathDelayOp : SDFOp<"path_delay", [HasParent<"SDFCellOp">]> {
  let summary = "annotate an unconditional, conditional, or fallback path delay";
  let description = [{
    Records an IOPATH, COND, or CONDELSE annotation between input and output
    ports, in absolute or incremental mode. COND requires a condition; the
    other kinds forbid one. The delay list has 1, 2, 3, 6, or 12 entries.
  }];
  let arguments = (ins SDFDelayMode:$mode, SDFPathKind:$kind,
      SDFPortAttr:$input, SDFPortAttr:$output,
      OptionalAttr<SDFConditionAttr>:$condition,
      SDFDelayValueArrayAttr:$delays);
  let assemblyFormat = [{
    $mode $kind qualified($input) `to` qualified($output)
    (`when` qualified($condition)^)? `delays` $delays attr-dict
  }];
  let hasVerifier = 1;
}

def SDFTimingCheckOp : SDFOp<"timing_check", [HasParent<"SDFCellOp">]> {
  let summary = "annotate timing-check events, limits, and conditions";
  let description = [{
    Preserves the timing-check kind, ordered events and limits, and optional
    timestamp and timecheck conditions. The verifier checks the event and
    limit counts required by the selected kind.
  }];
  let arguments = (ins SDFTimingCheckKind:$kind,
      SDFTimingEventArrayAttr:$events, SDFDelayValueArrayAttr:$limits,
      OptionalAttr<SDFConditionAttr>:$timestamp_condition,
      OptionalAttr<SDFConditionAttr>:$timecheck_condition);
  let assemblyFormat = [{
    $kind $events `limits` $limits
    (`scond` qualified($timestamp_condition)^)?
    (`ccond` qualified($timecheck_condition)^)? attr-dict
  }];
  let hasVerifier = 1;
}

def SDFLabelOp : SDFOp<"label", [HasParent<"SDFCellOp">]> {
  let summary = "annotate one named timing parameter";
  let description = [{
    Associates a nonempty label name with a delay value and an absolute or
    incremental annotation mode. Frontend annotation resolves the name in the
    selected cell instance.
  }];
  let arguments = (ins SDFDelayMode:$mode, StrAttr:$name,
      SDFDelayValueAttr:$value);
  let assemblyFormat = "$mode $name `=` qualified($value) attr-dict";
  let hasVerifier = 1;
}

def SDFInterconnectDelayOp
    : SDFOp<"interconnect_delay", [HasParent<"SDFCellOp">]> {
  let summary = "annotate a delay between hierarchical port endpoints";
  let description = [{
    Records the source and destination ports, annotation mode, and 1, 2, 3,
    6, or 12 delay values for an INTERCONNECT record.
  }];
  let arguments = (ins SDFDelayMode:$mode, SDFPortAttr:$source_port,
      SDFPortAttr:$destination_port, SDFDelayValueArrayAttr:$delays);
  let assemblyFormat = [{
    $mode qualified($source_port) `to` qualified($destination_port)
    `delays` $delays attr-dict
  }];
  let hasVerifier = 1;
}

def SDFTerminalDelayOp
    : SDFOp<"terminal_delay", [HasParent<"SDFCellOp">]> {
  let summary = "annotate a port, net, or device delay";
  let description = [{
    Records a PORT, NETDELAY, or DEVICE annotation with 1, 2, 3, 6, or 12
    delay values. PORT and NETDELAY require a terminal; DEVICE may omit it.
  }];
  let arguments = (ins SDFDelayMode:$mode, SDFTerminalDelayKind:$kind,
      OptionalAttr<SDFPortAttr>:$terminal,
      SDFDelayValueArrayAttr:$delays);
  let assemblyFormat = [{
    $mode $kind (qualified($terminal)^)? `delays` $delays attr-dict
  }];
  let hasVerifier = 1;
}

def SDFPulseOp : SDFOp<"pulse", [HasParent<"SDFCellOp">]> {
  let summary = "annotate pulse rejection and error limits";
  let description = [{
    Preserves PATHPULSE or PATHPULSEPERCENT rejection and error limits. Input
    and output ports are either both present to select a path, or both absent
    for a cell-wide record. The kind distinguishes time limits from
    percentages.
  }];
  let arguments = (ins SDFPulseKind:$kind,
      OptionalAttr<SDFPortAttr>:$input, OptionalAttr<SDFPortAttr>:$output,
      SDFDelayValueAttr:$reject, SDFDelayValueAttr:$error);
  let assemblyFormat = [{
    $kind (`from` qualified($input)^)? (`to` qualified($output)^)?
    `reject` qualified($reject) `error` qualified($error) attr-dict
  }];
  let hasVerifier = 1;
}

#endif // TALOS_DIALECT_SDF_SDFOPS_TD
