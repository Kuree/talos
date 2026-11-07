#ifndef TALOS_DIALECT_UPF_OPS_TD
#define TALOS_DIALECT_UPF_OPS_TD
include "talos/Dialect/UPF/UPFDialect.td"
include "talos/Dialect/UPF/UPFAttrs.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
def UPFSupplyEquivalenceOp : Op<UPFDialect, "equivalent", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "declared supply equivalence and substitution constraints";
  let description = [{
    A homogeneous list of supply roots or supply sets records a 6.44 user
    constraint. Electrical declarations merge physical rail identities;
    interchangeable declarations preserve distinct rails and their policies.
    Functional declarations also preserve distinct rails and prohibit replacing
    any listed object by another listed object. That prohibition retains the
    original object granularity: it is not a transitive non-equivalence class,
    and a set prohibition does not prohibit its shared ground replacing itself.
    These compiler-only declarations are consumed before runtime encoding.
  }];
  let arguments = (ins FlatSymbolRefArrayAttr:$objects,
      UPFSupplyEquivalenceKind:$kind);
  let assemblyFormat = "$objects `kind` $kind attr-dict";
  let hasVerifier = 1;
}
def UPFContextsOp : Op<UPFDialect, "contexts", []> {
  let summary = "design-top contexts visited by UPF source execution";
  let description = [{
    Preserves standalone block boundaries independently of navigation scopes.
    Port supply assumptions have different meaning inside and outside these
    contexts. This compiler-only inventory introduces no physical ownership.
  }];
  let arguments = (ins StrArrayAttr:$roots);
  let assemblyFormat = "$roots attr-dict";
  let hasVerifier = 1;
}
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
def UPFModelAttributesOp : Op<UPFDialect, "model_attributes", []> {
  let summary = "source model attribute association and UPF declaration context";
  let description = [{
    Retains provenance of an immediate model association. Its resolved object
    properties are recorded by design_attributes operations; this operation
    must not be reapplied against later hierarchy or macro classifications.
    Both annotations are compiler-only and consumed by UPF elaboration.
  }];
  let arguments = (ins StrAttr:$model, DictionaryAttr:$properties,
      StrAttr:$scope, StrAttr:$top);
  let assemblyFormat = "$model `properties` $properties `scope` $scope `top` $top attr-dict";
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
      DefaultValuedAttr<BoolAttr, "false">:$soft_macro,
      OptionalAttr<DictionaryAttr>:$properties,
      OptionalAttr<StrAttr>:$scope,
      OptionalAttr<StrAttr>:$top);
  let assemblyFormat = "$element attr-dict";
  let hasVerifier = 1;
}
def UPFPortAttributesOp : Op<UPFDialect, "port_attributes", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "resolved per-property attributes on a logical port window";
  let description = [{
    Identifies a declared port independently of aliased storage. Offsets are
    logical packed bits of that port, before applying its physical source_low.
    A zero source_width denotes an opaque whole port; partial consumers must
    reject an unsupported representation rather than infer storage geometry.
    A model names provenance on an uninstantiated model port, with no runtime
    effect. Source scope/top preserve terminal authority. Supply assumptions
    apply only on the appropriate side of a terminal or design-top boundary.
    These compiler-only annotations retain explicit values, including FALSE.
  }];
  let arguments = (ins StrAttr:$port, I64Attr:$offset, I64Attr:$width,
      I64Attr:$source_width, DictionaryAttr:$properties,
      StrAttr:$scope, StrAttr:$top,
      OptionalAttr<StrAttr>:$model,
      OptionalAttr<FlatSymbolRefAttr>:$driver_supply,
      OptionalAttr<FlatSymbolRefAttr>:$receiver_supply);
  let assemblyFormat = "$port `at` $offset `width` $width `of` $source_width `properties` $properties `scope` $scope `top` $top attr-dict";
  let hasVerifier = 1;
}
def UPFPortBindingOp : Op<UPFDialect, "port_binding", []> {
  let summary = "immutable formal-port to connection actor identity";
  let description = [{
    Binds a port's child scope and formal ordinal to its original code-unit ID.
    Output connection actors execute in the parent scope; their lexical scope
    and printed hierarchical names cannot recover this declaration identity.
    This compiler-only record is consumed before scheduling and encoding.
  }];
  let arguments = (ins I64Attr:$scope, I64Attr:$ordinal, I64Attr:$actor,
      DefaultValuedAttr<BoolAttr, "false">:$opaque);
  let assemblyFormat = "`scope` $scope `ordinal` $ordinal `actor` $actor attr-dict";
}
def UPFPortValueOp : Op<UPFDialect, "port_value", [Pure, SameOperandsAndResultType]> {
  let summary = "identity of a logical output connection's published value";
  let description = [{
    Marks the converted formal value before evaluating its actual lvalue.
    Isolation rewrites this value rather than incidental writes in the actor.
    The actor is the original code-unit ID from port_binding. This pure
    compiler-only identity is removed before scheduling and runtime encoding.
  }];
  let arguments = (ins AnyType:$input, I64Attr:$actor);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input `actor` $actor attr-dict `:` type($input)";
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
    materialized_functions distinguishes genuine bound/abstract function
    identities from unused placeholders. It includes all required functions;
    omission in legacy raw IR means that only required roles are populated.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, DictionaryAttr:$functions,
      StrArrayAttr:$required, OptionalAttr<UPFPowerStateArrayAttr>:$states,
      OptionalAttr<FlatSymbolRefArrayAttr>:$associated,
      OptionalAttr<FlatSymbolRefAttr>:$owner,
      DefaultValuedAttr<BoolAttr, "false">:$complete,
      OptionalAttr<StrAttr>:$strategy,
      OptionalAttr<FlatSymbolRefAttr>:$binding,
      OptionalAttr<StrArrayAttr>:$materialized_functions);
  let assemblyFormat = "$sym_name `functions` $functions `required` $required attr-dict";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    /// Actual bound/abstract identities, independently of usage requirements.
    /// Legacy raw fields outside `required` may be unpopulated placeholders.
    ::mlir::ArrayAttr getPopulatedFunctions();
  }];
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

    anonymous_parent identifies a compiler-derived hard-macro domain. It shares
    the physical parent's exact primary supply and policies, but owns a distinct
    extent and inherits no strategies or switch definitions. Resolution rebuilds
    these owners from explicit declarations. Even a private domain has semantic
    effects when its symbol is unused, so symbol DCE cannot discard it.
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
      DefaultValuedAttr<BoolAttr, "false">:$atomic,
      // Source authority for parent isolation placement across macro bounds.
      OptionalAttr<StrAttr>:$isolation_top,
      // Derived 6.20 ownership. Shares the physical parent's exact primary
      // supply and policies, without copying its strategies or switch.
      OptionalAttr<FlatSymbolRefAttr>:$anonymous_parent,
      DefaultValuedAttr<BoolAttr, "true">:$isolation_use_functional_equivalence);
  let assemblyFormat = "$sym_name `elements` $elements `power` $power `on` $on attr-dict";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    /// Membership after global extent resolution, or in the local effective
    /// element list when no resolved extent has been attached yet.
    bool containsPath(::llvm::StringRef path);
    bool canDiscardOnUseEmpty() { return false; }
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
