//===- SAIFDialect.td - IEEE 1801 Annex I data ------------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFDIALECT_TD
#define TALOS_DIALECT_SAIF_SAIFDIALECT_TD

include "mlir/IR/DialectBase.td"

def SAIFDialect : Dialect {
  let name = "saif";
  let cppNamespace = "::talos::saif";
  let summary = "IEEE 1801-2018 Annex I switching activity interchange";
  let description = [{
    Ordered, compiler-only data for backward SAIF activity, library forward
    directives, and RTL forward mappings. A recursive descent importer emits
    these operations directly. Verification owns record placement, header
    structure, defaults, and semantic constraints independently of the source
    parser. Conditions are typed postfix expressions; names retain component
    and bit-select boundaries after character unescaping.

    This dialect describes exchange data, not executable power intent.
    Binding and collection lower into the existing simulation machinery.

    The driver accepts `--saif=activity.saif` to collect source-authored
    integral signals, fixed packed/unpacked arrays, records and unions.
    `--saif-input=mapping.saif` optionally selects and renames points using
    RTL forward mappings, including virtual instance PORT data. Library forward
    inputs select cell-type state/path conditions, edge splitting and leakage
    conditions. Backward inputs describe results and cannot configure collection.

    `talos-sim-prepare-saif` resolves names before optimization and stores
    verified per-bit bindings on the module. Native lowering emits a constant
    registration table, and the runtime observes actual committed values in
    both native and bytecode execution. With UPF, these include published
    corruption, isolation and retention outputs. Residence times T0/T1/TX/TZ
    are exact femtosecond integers; TC counts only 0-to-1 and 1-to-0 changes,
    including intermediate changes within one scheduler slot. TB observes
    independent opposing drivers; IG/IK observe rejected timed pulses. TG
    estimates excess TC over the complete observation window against a
    separately settled zero-delay reference of certified combinational
    processes. It does not identify individual analog glitch pulses.
    State/path TG estimates are apportioned over measured pre-input TC
    histograms, with consistent totals and rise/fall budgets. Sequential,
    external and unsupported process outputs form reference boundaries;
    user code with side effects is
    executed by the primary simulation. State/path counts retain the cell state
    before the causal input transition through scheduled output delivery.

    Aggregate member names are flattened into a signal basename; the last
    nonnegative array/bit select remains a canonical SAIF index. Ambiguous
    flattened names are diagnosed rather than silently dropping observations.
  }];
  let useDefaultAttributePrinterParser = 1;
  let usePropertiesForAttributes = 0;
  let hasOperationAttrVerify = 1;
  let discardableAttrs = (ins
    "::mlir::StringAttr":$output,
    "::mlir::ArrayAttr":$bindings,
    "::mlir::ArrayAttr":$cells
  );
}

#endif // TALOS_DIALECT_SAIF_SAIFDIALECT_TD
