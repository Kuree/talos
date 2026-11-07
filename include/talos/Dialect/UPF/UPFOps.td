#ifndef TALOS_DIALECT_UPF_OPS_TD
#define TALOS_DIALECT_UPF_OPS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFAttrs.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
def UPFHierarchyOp : Op<UPFDialect, "hierarchy", []> {
  let summary = "compiler-only HDL hierarchy for declarative UPF selection";
  let description = [{
    Preserves component-aware parent links of active instances and generate
    scopes. Simulation reflection can elide lexical generate scopes without
    changing UPF selection, traversal or selector precedence. This semantic
    inventory is consumed during UPF elaboration and has no runtime cost.
  }];
  let arguments = (ins ArrayAttr:$scopes);
  let assemblyFormat = "$scopes attr-dict";
  let hasVerifier = 1;
}
def UPFRetentionElementsOp : Op<UPFDialect, "retention_elements", [Symbol]> {
  let summary = "named collective-state constraint (IEEE 1801 6.51)";
  let description = [{
    Preserves the declaration scope, aggregate typed HDL selectors and filters.
    A retention strategy can reference this symbol without converting implied
    registers into explicit signal selectors. Membership and collective-state
    coverage are resolved against the final physical state and domain extents.
    This declaration supplies no save/restore controls and creates no runtime
    storage or processes by itself.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, StrAttr:$scope,
      ArrayAttr:$elements, ArrayAttr:$excluded,
      OptionalAttr<UPFRetentionFilter>:$applies_to,
      DefaultValuedAttr<UPFRetentionPurpose, "::talos::upf::RetentionPurpose::Required">:$purpose,
      DefaultValuedAttr<BoolAttr, "true">:$transitive);
  let assemblyFormat = "$sym_name `scope` $scope `elements` $elements attr-dict";
  let hasVerifier = 1;
}
def UPFDesignAttributesOp : Op<UPFDialect, "design_attributes", []> {
  let summary = "resolved HDL object attributes used by UPF selection";
  let description = [{
    Records an object's retention requirement and leaf boundary after resolving
    model and instance attribute precedence. Filtering precedes projection to
    the object's implied state; attributes do not inherit into child instances.
    These annotations are consumed with the declarative UPF intent.
  }];
  let arguments = (ins UPFRetentionElementAttr:$element,
      OptionalAttr<UPFRetentionPurpose>:$retention,
      DefaultValuedAttr<BoolAttr, "false">:$hard_macro,
      DefaultValuedAttr<BoolAttr, "false">:$soft_macro);
  let assemblyFormat = "$element attr-dict";
  let hasVerifier = 1;
}
def UPFSupplyOp : Op<UPFDialect, "supply", [Symbol]> {
  let summary = "one shared root supply value and its absolute handle aliases";
  let description = [{
    Declares one supply root shared by all entries in `names`, which must be
    unique absolute handle names. `initial_value` packs the supply state into
    bits 1:0 and signed 32-bit microvolts into bits 33:2. `writable` identifies
    externally controlled roots. An `always_on` root is protected from writes
    and starts FULL_ON.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$names,
      BoolAttr:$writable, DefaultValuedAttr<I64Attr, "0">:$initial_value,
      DefaultValuedAttr<BoolAttr, "false">:$always_on);
  let assemblyFormat = "$sym_name `names` $names `writable` `=` $writable attr-dict";
  let hasVerifier = 1;
}
def UPFSupplySetOp : Op<UPFDialect, "supply_set", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "supply-set identity with resolved function roots and requirements";
  let description = [{
    Maps all six standard supply functions to `upf.supply` roots. `required`
    records the subset used by the resolved intent. Associated sets retain
    distinct identities while sharing corresponding function roots and
    required functions, with reciprocal association links.

    Optional power states retain typed predicates and simulation states.
    Strategy-local handles also identify their owning domain and strategy;
    a binding names an associated supplier.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, DictionaryAttr:$functions,
      StrArrayAttr:$required, OptionalAttr<UPFPowerStateArrayAttr>:$states,
      OptionalAttr<FlatSymbolRefArrayAttr>:$associated,
      OptionalAttr<FlatSymbolRefAttr>:$owner,
      DefaultValuedAttr<BoolAttr, "false">:$complete,
      OptionalAttr<StrAttr>:$strategy,
      OptionalAttr<FlatSymbolRefAttr>:$binding);
  let assemblyFormat = "$sym_name `functions` $functions `required` $required attr-dict";
  let hasVerifier = 1;
}
def UPFDomainOp : Op<UPFDialect, "domain", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "resolved power domain with supply roots and optional switch";
  let description = [{
    Identifies the HDL elements governed by a power domain and its resolved
    power, ground, input, and primary supply bindings. Named switch conditions
    distinguish on, partial, off, and error states. Isolation attributes retain
    the control polarity, clamp value, and supply-comparison policy; retention
    attributes retain resolved selectors, control events, and strategy supply
    handles for UPF lowering.

    Aggregate selectors are preserved independently of the derived `extent`.
    An atomic domain protects its normalized extent against later partitioning;
    explicit exclusions can leave holes for other domains.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, StrArrayAttr:$elements,
      FlatSymbolRefAttr:$power, OptionalAttr<FlatSymbolRefAttr>:$ground,
      OptionalAttr<FlatSymbolRefAttr>:$input,
      OptionalAttr<FlatSymbolRefAttr>:$primary,
      OptionalAttr<FlatSymbolRefArrayAttr>:$policies,
      UPFSwitchStateArrayAttr:$on, OptionalAttr<UPFSwitchStateArrayAttr>:$partial,
      OptionalAttr<UPFSwitchStateAttr>:$off,
      OptionalAttr<UPFSwitchStateArrayAttr>:$errors,
      OptionalAttr<StrAttr>:$isolation_control,
      DefaultValuedAttr<BoolAttr, "true">:$isolation_high,
      DefaultValuedAttr<I64Attr, "0">:$clamp,
      OptionalAttr<UPFRetentionArrayAttr>:$retentions,
      OptionalAttr<StrAttr>:$isolation_name,
      // IEEE 1801 6.45: omitted/bare is TRUE; FALSE removes only the
      // driver/receiver supply comparison from isolation's port filters.
      DefaultValuedAttr<BoolAttr, "true">:$isolation_diff_supply_only,
      OptionalAttr<StrArrayAttr>:$excluded_elements,
      OptionalAttr<UPFDomainExtentAttr>:$extent,
      DefaultValuedAttr<BoolAttr, "false">:$atomic);
  let assemblyFormat = "$sym_name `elements` $elements `power` $power `on` $on attr-dict";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    /// Membership after global extent resolution, or in the local effective
    /// element list when no resolved extent has been attached yet.
    bool containsPath(::llvm::StringRef path);
  }];
}
def UPFCompositeDomainOp : Op<UPFDialect, "composite_domain", [Symbol,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "power-domain container without a physical extent (1801 6.16)";
  let description = [{
    Retains composite identity, child domain references and a primary supply
    handle after compiler-time composition. Corresponding primary functions
    share roots after their preexisting equivalence has been checked. The
    container owns no HDL processes or corruption monitor. Its local primary
    state catalog does not become a subdomain's simulation policy.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name,
      FlatSymbolRefArrayAttr:$subdomains, FlatSymbolRefAttr:$primary);
  let assemblyFormat = "$sym_name `subdomains` $subdomains `primary` $primary attr-dict";
  let hasVerifier = 1;
}
#endif
