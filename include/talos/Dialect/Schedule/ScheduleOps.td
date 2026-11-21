// Scheduling plans and executable scheduler actions.
#ifndef TALOS_DIALECT_SCHEDULE_SCHEDULEOPS_TD
#define TALOS_DIALECT_SCHEDULE_SCHEDULEOPS_TD
include "talos/Dialect/Simulation/SimulationAttrs.td"
include "talos/Dialect/Simulation/SimulationTypes.td"
include "talos/Dialect/Simulation/SimulationResources.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/CallInterfaces.td"
include "mlir/Interfaces/ViewLikeInterface.td"
include "talos/Dialect/Schedule/ScheduleAttrs.td"
include "mlir/Dialect/LLVMIR/LLVMTypes.td"
include "talos/Dialect/Runtime/RuntimeTypes.td"
class ScheduleNativeOp<string mnemonic, list<Trait> traits = []>
    : Op<ScheduleDialect, mnemonic, traits> {
  let assemblyFormat = "operands attr-dict `:` functional-type(operands, results)";
}
def NativeWordRegionOp : ScheduleNativeOp<"word.region", [
    RecursiveMemoryEffects,
    DeclareOpInterfaceMethods<RegionBranchOpInterface,
                              ["getRegionInvocationBounds"]>]> {
  let summary = "execute a proven native-width packed computation";
  let description = [{
    Executes the enclosed non-suspending CFG once, in program order. Packed
    updates fit the declared maximum native word width, between 2 and 64 bits.
    If lane_count is nonzero, each update contains that many complete scalar
    elements; independent fields can retain different element widths. A zero
    lane_count denotes the legacy form with all updates at the declared width. Both
    value and unknown planes remain exact; width does not imply two-state.
    Formation proves bounded lane iteration, contained selectors, independent
    lane dataflow, and unobservable intermediate publications before replacing
    scalar iterations. Calls, overrides and other observation boundaries are
    not permitted. Conversion only removes the representation boundary; it
    must not rediscover eligibility or scalarize a word into individual bits.
    The entry block has no arguments and exits use word.yield.
  }];
  let arguments = (ins I32Attr:$width,
                       DefaultValuedAttr<I32Attr, "0">:$lane_count);
  let regions = (region AnyRegion:$body);
  let assemblyFormat = "$width $body attr-dict";
  let hasVerifier = 1;
}
def NativeWordYieldOp : ScheduleNativeOp<"word.yield",
    [Terminator, HasParent<"NativeWordRegionOp">, Pure,
     DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface>]> {
  let summary = "finish a native packed computation region";
  let assemblyFormat = "attr-dict";
}
def NativeWordTableOp : ScheduleNativeOp<"word.table", [Pure]> {
  let summary = "evaluate an exact scalar truth table independently in each lane";
  let description = [{
    Operands and result have one common word width (2 through 64), using either
    integer bits or exact four-state logic. Each table index consists of each
    operand's value bit followed by its unknown bit for four-state operands.
    Table entries supply the result's value and unknown bits. The tables have
    2^P entries, where P is the number of operand planes, at most six. This
    represents scalar arithmetic, comparisons and selections without allowing
    carries, reductions or control predicates to cross independent lanes.
    Conversion emits Boolean word operations, never a per-bit loop or helper.
  }];
  let arguments = (ins Variadic<AnyType>:$inputs, APIntAttr:$value_table,
                       APIntAttr:$unknown_table);
  let results = (outs AnyType:$result);
  let hasVerifier = 1;
}
def NativeWordReverseOp : ScheduleNativeOp<"word.reverse", [Pure]> {
  let summary = "reverse native elements, preserving both four-state planes";
  let arguments = (ins AnyType:$input, DefaultValuedAttr<I32Attr, "1">:$lane_width);
  let results = (outs AnyType:$result);
  let hasVerifier = 1;
  let hasFolder = 1;
}
def NativeWordResizeLanesOp : ScheduleNativeOp<"word.resize_lanes", [Pure]> {
  let summary = "resize each native storage lane without changing its bit order";
  let description = [{
    Treats the input and result as equal-length sequences of integer lanes.
    Each lane is independently truncated or zero-extended. Four-state value
    and unknown planes undergo the same transformation, preserving X and Z.
    This bridges packed logical lanes and padded physical array slots without
    scalar memory accesses. Lowering uses LLVM vector integer conversions.
  }];
  let arguments = (ins AnyType:$input, I32Attr:$input_lane_width,
                       I32Attr:$result_lane_width);
  let results = (outs AnyType:$result);
  let hasVerifier = 1;
  let hasFolder = 1;
}
def NativeWordViewOp : ScheduleNativeOp<"word.view", [Pure, ViewLikeOpInterface]> {
  let summary = "view consecutive scalar array storage lanes as one packed word";
  let description = [{
    Selects a packed native word from the canonical storage of a fixed unpacked
    array of packed elements. low_bit is a physical storage offset:
    unpacked elements are ordered from the declaration's left bound. This is
    a storage view, not a SystemVerilog packed cast or streaming expression.
    The formation pass proves containment and equal state domains. Invalid
    offsets produce an invalid reference, as for native reference selectors.
  }];
  let arguments = (ins SimRefType:$input, AnySignlessInteger:$low_bit);
  let results = (outs SimRefType:$result);
  let extraClassDeclaration = [{
    ::mlir::Value getViewSource() { return getInput(); }
  }];
  let hasVerifier = 1;
}
def NativeWordExtractOp : ScheduleNativeOp<"word.extract", [Pure]> {
  let summary = "extract a native word from canonical unpacked SSA storage";
  let description = [{
    Extracts consecutive bits of a fixed unpacked array of packed elements.
    low_bit is a physical storage offset, with elements ordered from the
    declaration's left bound. Value and unknown planes retain that order;
    this operation does not perform a packed cast or streaming conversion.
    The result has the same state domain as the element. A negative offset
    or a word extending past the array returns the result's default value
    (all X for logic, zero for an integer). Formation proves containment.
  }];
  let arguments = (ins AnyType:$input, AnySignlessInteger:$low_bit);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$input `from` $low_bit attr-dict `:` functional-type(operands, results)";
  let hasVerifier = 1;
}
def TransferActivationOp : ScheduleNativeOp<"transfer.activation",
    [DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "one ordered continuous copy activation and its source wait";
  let description = [{
    IEEE 1800 4.9.1, 4.9.6, 9.4.2 and 10.6.2.
    Binds an original process to a continuous transfer between entry storage
    captures. The process executes initially and on each source change, in
    Active, retaining its identity, canonical frame, wait and publication.
    Source and destination remain distinct handles even when implementations
    are shared. A transfer samples the source, performs the complete continuous
    assignment (including force/release contribution), and then arms its wait.
    It must not be interpreted as an alias or as a final-value-only update.

    signature, source, destination and capture_offsets specify the canonical
    capture ABI. -1 offsets identify context captures supplied by the instance.
    Without kernel, this actor has its own table-process entry. With kernel,
    it uses the shared implementation selected by Schedule optimization;
    representation conversion must not regroup activations.
  }];
  let arguments = (ins SymbolRefAttr:$actor, TypeAttr:$signature,
      I32Attr:$source, I32Attr:$destination,
      DenseI64ArrayAttr:$capture_offsets,
      OptionalAttr<FlatSymbolRefAttr>:$kernel);
  let hasVerifier = 1;
}
def TransferKernelOp : ScheduleNativeOp<"transfer.kernel", [Symbol]> {
  let summary = "shared implementation of ordered continuous transfers";
  let description = [{
    IEEE 1800 4.9.1 and 10.3.2: code sharing preserves separate updates.
    Implements the transfer semantics of transfer.activation using the
    executing instance's context and canonical storage captures. No storage
    identity, source owner, continuation ID or wait record is baked into this
    kernel. Each activation supplies those through its own instance and wait
    plan. All sharing and ABI compatibility decisions precede conversion.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, TypeAttr:$signature,
      I32Attr:$source, I32Attr:$destination,
      DenseI64ArrayAttr:$capture_offsets);
  let hasVerifier = 1;
}
// Executable actions retain facts that used to be recovered from runtime-call
// names and the shape of expanded LLVM loads/stores.
def NativeKnownValueOp : ScheduleNativeOp<"known.value", [Pure]> {
  let summary = "test the complete unknown plane of a fixed native value";
  let description = [{
    Establishes that every represented bit of input is two-state. Fixed
    unpacked arrays and structs retain their native value/unknown planes;
    there is no bit-stream export, allocation, runtime call or state effect.
    This predicate proves knownness only, not equality, visibility or bounds.
  }];
  let arguments = (ins AnyType:$input);
  let results = (outs I1:$known);
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
}
def NativeKnownRootsOp : ScheduleNativeOp<"known.roots"> {
  let summary = "test that whole storage roots match their steady unknown planes";
  let description = [{
    True when every referenced storage root holds X or Z exactly in the bits
    of its steady pattern (`simulation.steady_unknown`, none without one) and
    nowhere else. Each reference addresses a whole root. Generated code tests
    one summary bit per root, which every writer that may make the root differ
    from its pattern sets and the runtime clears after comparing the root's
    unknown plane with the pattern, so the predicate never claims a root the
    summary does not track.
  }];
  let arguments = (ins
      Arg<Variadic<SimRefType>, "", [MemRead<SimStorageResource>]>:$references);
  let results = (outs I1:$known);
  let assemblyFormat = [{
    $references attr-dict `:` qualified(type($references))
  }];
  let hasVerifier = 1;
}
def NativeTransitionOp
    : ScheduleNativeOp<
          "transition",
          [MemoryEffects<
              [MemRead, MemWrite, MemRead<SimStorageResource>,
               MemWrite<SimStorageResource>, MemRead<SimSchedulerResource>,
               MemWrite<SimSchedulerResource>, MemRead<SimProcessResource>,
               MemWrite<SimProcessResource>, MemRead<SimExternalResource>,
               MemWrite<SimExternalResource>]>]> {
  let summary = "publish one exact scalar four-state transition";
  let description = [{
    Publishes the captured old/new value and unknown planes of one store in
    the executing process's current event region. The offset is relative to
    the static root, and width is between 1 and 64. Dynamic offsets retain
    their original selector semantics. source_owner identifies the original
    logical process, including inside a fused activation; its absence requires
    runtime source resolution. Publication is synchronous and may deliver
    observers/callbacks. It is never a final-value-only notification and may
    not be moved across another effect or coalesced with another occurrence.
  }];
  let arguments = (ins LLVM_AnyPointer:$context, I64:$offset, I64:$old_value,
      I64:$old_unknown, I64:$new_value, I64:$new_unknown, I64Attr:$static_state,
      I64Attr:$width, OptionalAttr<ScheduleSourceOwnerAttr>:$source_owner);
  let hasVerifier = 1;
}
// The generated eval ready sets (ReadySet) are named by their globals. A
// ready action names its set and the leaf word it updates or reads; its
// capacity freezes the set's DirtyReadySetLayout.
def NativeReadyUpdateOp
    : ScheduleNativeOp<"ready.update", [
          DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
          DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "add or consume an exact word of pending fine activations";
  let description = [{
    Updates the authoritative DirtyReadySetLayout leaf `word` of the ready
    set `set` and its dirty levels.
    With consume=false it unions mask and, when mask may be nonzero, sets the
    leaf's dirty bit at every level; with consume=true it removes mask from
    the leaf only (dirty bits are cleared by the reader that sees the child
    empty).
    capacity freezes the ready universe and word identifies the leaf, without
    recovering either from addresses. These are pending activations, not
    event history. Ordered updates may be combined only while no selection,
    observer, callback, opaque alias, or handoff can observe intermediate
    storage. All leaves/indexes must be materialized at those boundaries.
  }];
  let arguments = (ins FlatSymbolRefAttr:$set, I64:$mask, I64Attr:$capacity,
      I64Attr:$word, BoolAttr:$consume);
  let assemblyFormat = "$set `[` $word `]` `,` $mask attr-dict";
  let builders = [OpBuilder<(ins "::talos::schedule::ReadySet":$set,
                                 "::mlir::Value":$mask, "uint64_t":$capacity,
                                 "uint64_t":$word, "bool":$consume)>];
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}
def NativeReadyCommitOp
    : ScheduleNativeOp<"ready.commit", [
          DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
          DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "materialize one SSA pending-word update and its indexes";
  let description = [{
    Replaces a certified unobserved sequence of ordered add/consume actions
    on leaf `word` of the ready set `set`.
    The resulting pending word is (previous & ~remove_mask) | add_mask.
    SSA masks include every intervening consume; event publications remain
    distinct ordered effects. Materializes the authoritative leaf and derived
    indexes together before any selection, observer or handoff boundary.
  }];
  let arguments = (ins FlatSymbolRefAttr:$set, I64:$remove_mask,
      I64:$add_mask, I64Attr:$capacity, I64Attr:$word);
  let assemblyFormat =
      "$set `[` $word `]` `,` $remove_mask `,` $add_mask attr-dict";
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}
def NativeReadyMergeOp
    : ScheduleNativeOp<"ready.merge", [
          DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
          DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "add an ascending bitmap to a pending set and its indexes";
  let description = [{
    Reads ceil(capacity / 64) i64 words from source in ascending order. Each
    word is read immediately before adding its bits to the corresponding
    DirtyReadySetLayout leaf of the ready set `set` and setting that leaf's
    dirty bits. Bits above capacity in the last source word are ignored.
    Source may overlap the set; earlier leaf/dirty writes are visible to later
    source reads. Source addresses storage aligned to at least eight bytes.
    The lowering may first test a group of consecutive words for emptiness and
    skip an empty group: a skipped group adds nothing, so the result equals
    the word-by-word merge.

    This is an ordered scheduler effect, with no actor, callback, selection or
    checkpoint inside it. Pending ready updates must be materialized before
    the merge, and its leaves and dirty bits are visible to every subsequent
    observer. It does not consume the source.
  }];
  let arguments = (ins FlatSymbolRefAttr:$set, LLVM_DefaultPointer:$source,
      I64Attr:$capacity);
  let assemblyFormat = "$set `,` $source attr-dict";
  let builders = [OpBuilder<(ins "::talos::schedule::ReadySet":$set,
                                 "::mlir::Value":$source,
                                 "uint64_t":$capacity)>];
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}
def NativeReadyReadOp : ScheduleNativeOp<"ready.read", [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "inspect the current pending leaf, including region-local updates";
  let description = [{
    Reads the authoritative pending leaf `word` of the ready set `set` without
    consuming it. Within a
    ready.region the result includes all preceding ordered add/consume actions
    in that region; it does not require materializing derived indexes. Opaque
    accesses, calls and handoffs still require coherent physical storage.
    This reads pending activation state, not event history (LRM 4.3--4.7).
  }];
  let arguments = (ins FlatSymbolRefAttr:$set, I64Attr:$capacity,
      I64Attr:$word);
  let results = (outs I64:$value);
  let assemblyFormat = "$set `[` $word `]` attr-dict";
  let builders = [OpBuilder<(ins "::talos::schedule::ReadySet":$set,
                                 "uint64_t":$capacity, "uint64_t":$word)>];
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}
// The words of a generated eval ready set (ReadySet), a leaf or a dirty-level
// word of its DirtyReadySetLayout, read and written whole. Outside ready
// actions, functions access a set's storage only through these operations.
//
// What native passes need to know about an access is a property:
// - activation_entry (loads): the access reads the leaf that selects member
//   `activation_entry` of an activation group, its executable entry;
// - owner: the activation-group member whose activation performs the access.
def NativeReadyWordLoadOp : ScheduleNativeOp<"ready.word.load", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read a word of a generated eval ready set";
  let description = [{
    Reads the 64-bit word `static_word` plus the optional `dynamic_word` of
    the ready set `set`. This reads pending activations, not event history
    (IEEE 1800-2023 4.3).
  }];
  let arguments = (ins Arg<FlatSymbolRefAttr, "the set's global",
                           [MemRead]>:$set,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$activation_entry,
                       OptionalAttr<I32Attr>:$owner);
  let results = (outs I64:$result);
  let assemblyFormat = [{
    $set `[` custom<StateOffset>($dynamic_word, $static_word) `]` attr-dict
  }];
  let builders = [OpBuilder<(ins "::talos::schedule::ReadySet":$set,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}

def NativeReadyWordStoreOp : ScheduleNativeOp<"ready.word.store", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write a word of a generated eval ready set";
  let description = [{
    Writes `value` to the 64-bit word `static_word` plus the optional
    `dynamic_word` of the ready set `set`.
  }];
  let arguments = (ins I64:$value,
                       Arg<FlatSymbolRefAttr, "the set's global",
                           [MemWrite]>:$set,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$owner);
  let assemblyFormat = [{
    $value `,` $set `[` custom<StateOffset>($dynamic_word, $static_word) `]`
    attr-dict
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value,
                                 "::talos::schedule::ReadySet":$set,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::ReadySet getReadySet();
  }];
  let hasVerifier = 1;
}

// The words of a generated eval mask (EvalMask), read and written whole.
// A mask is no ready set: its words carry no pending activations, so ready
// regions and activation groups see these as plain accesses of other memory.
// The runtime's proof certificates also address mask words directly.
//
// What native passes need to know about an access is a property:
// - owner: the activation-group member whose activation performs the access.
def NativeMaskLoadOp : ScheduleNativeOp<"mask.load", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read a word of a generated eval mask";
  let description = [{
    Reads the 64-bit word `static_word` plus the optional `dynamic_word` of
    the generated eval mask `mask`.
  }];
  let arguments = (ins Arg<FlatSymbolRefAttr, "the mask's global",
                           [MemRead]>:$mask,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$owner);
  let results = (outs I64:$result);
  let assemblyFormat = [{
    $mask `[` custom<StateOffset>($dynamic_word, $static_word) `]` attr-dict
  }];
  let builders = [OpBuilder<(ins "::talos::schedule::EvalMask":$mask,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::EvalMask getEvalMask();
  }];
  let hasVerifier = 1;
}

def NativeMaskStoreOp : ScheduleNativeOp<"mask.store", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write a word of a generated eval mask";
  let description = [{
    Writes `value` to the 64-bit word `static_word` plus the optional
    `dynamic_word` of the generated eval mask `mask`.
  }];
  let arguments = (ins I64:$value,
                       Arg<FlatSymbolRefAttr, "the mask's global",
                           [MemWrite]>:$mask,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$owner);
  let assemblyFormat = [{
    $value `,` $mask `[` custom<StateOffset>($dynamic_word, $static_word) `]`
    attr-dict
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value,
                                 "::talos::schedule::EvalMask":$mask,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::EvalMask getEvalMask();
  }];
  let hasVerifier = 1;
}

def NativeReadyRegionOp: ScheduleNativeOp<"ready.region", [RecursiveMemoryEffects]> {
  let summary = "carry pending readiness through a non-suspending CFG";
  let description = [{
    Execute the body in source order while representing ready.update and
    ready.commit actions as local remove/add masks. Materialize pending masks
    before opaque readiness inspection, potentially aliasing accesses, calls,
    observers and region exit. Disjoint ordinary storage accesses do not
    inspect readiness. Signal transitions and NBA actions retain their order
    and are observation boundaries. This changes pending-set representation,
    never event history or activation eligibility (IEEE 1800 4.3--4.7).
    ready.read observes the current local pending word without a flush.
    The region has no entry arguments; exits use ready.yield, whose operands
    become the region's results, so a function that returns a value keeps
    its CFG inside one region. Only flat CFG branches are allowed, with no
    suspensions or nested regions.
  }];
  let regions = (region AnyRegion:$body);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$body attr-dict (`:` type($results)^)?";
  let hasVerifier = 1;
}
def NativeReadyYieldOp : ScheduleNativeOp<"ready.yield",
    [Terminator, HasParent<"NativeReadyRegionOp">, Pure]> {
  let summary = "materialize pending readiness and leave its region";
  let arguments = (ins Variadic<AnyType>:$operands);
  let assemblyFormat = "($operands^ `:` type($operands))? attr-dict";
  let hasVerifier = 1;
}
def NativeNBABatchOp : ScheduleNativeOp<"nba.batch", [SingleBlock,
    MemoryEffects<[MemRead, MemWrite, MemRead<SimStorageResource>,
      MemWrite<SimStorageResource>, MemRead<SimSchedulerResource>,
      MemWrite<SimSchedulerResource>, MemRead<SimExternalResource>]>]> {
  let summary = "commit a certified private set of NBA roots at one barrier";
  let description = [{
    IEEE 1800 4.3, 4.5, 4.6, 4.9.4 and 10.4.2.
    Executes the commit actions in body at the current NBA barrier. Each root
    has already captured its RHS, destination and write mask during staging.
    Admission proves that intermediate values have no observers, except direct
    generated change consumers covered by the accumulator's transient mask.
    No edge, expression, runtime, clocking or external observer may be elided.
    These proofs concern observation, not source-language visibility.

    The region is a non-suspending commit boundary, not a time-slot boundary.
    Only nba.commit and nba.yield are permitted inside it. Commits may share
    guards and combine pending consumer activations; they cannot move into
    Active or across another barrier. Roots whose runtime guard fails remain
    pending for the canonical commit that must follow this region. A successful
    root commit consumes its staging record and only its own dirty bit. The
    changed flag is accumulated, and status reports a runtime error, if any.
    With barrier_local, a generated change consumer may reach an observer
    when Active resumes. Its source-order update cannot reach an immediate
    observer during this NBA drain. The runtime checks that observation
    environment before any root is consumed.
  }];
  let arguments = (ins LLVM_AnyPointer:$context, I32:$barrier,
      LLVM_AnyPointer:$changed, OptionalAttr<NBABatchLayoutAttr>:$layout,
      OptionalAttr<UnitAttr>:$barrier_local);
  let results = (outs I32:$status);
  let regions = (region AnyRegion:$body);
  let assemblyFormat = [{ $context `,` $barrier `,` $changed $body attr-dict
    `:` functional-type(operands, results) }];
  let hasVerifier = 1;
}
def NativeNBACommitOp : ScheduleNativeOp<"nba.commit",
    [HasParent<"NativeNBABatchOp">,
     MemoryEffects<[MemRead<SimStorageResource>, MemWrite<SimStorageResource>,
       MemRead<SimSchedulerResource>, MemWrite<SimSchedulerResource>]>]> {
  let summary = "consume certified private accumulator or fixed-slot staging";
  let arguments = (ins I64Attr:$root, OptionalAttr<NBACommitLayoutAttr>:$layout);
  let assemblyFormat = "$root attr-dict";
  let hasVerifier = 1;
}
def NativeNBAYieldOp : ScheduleNativeOp<"nba.yield",
    [Terminator, HasParent<"NativeNBABatchOp">, Pure]> {
  let summary = "finish a private NBA commit region";
  let assemblyFormat = "attr-dict";
}
class ScheduleNativeSuspendOp<string mnemonic, dag extraArgs = (ins),
                   list<Trait> extraTraits = []>
    : ScheduleNativeOp<mnemonic,
            !listconcat(
                [
                  Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
                  MemoryEffects<[
                    MemWrite<SimSchedulerResource>, MemWrite<SimProcessResource>
                  ]>
                ],
                extraTraits)> {
  let description = [{
    Registers a scheduler wait using physical handles and resumes at
    `continuation` with the captured `continuation_operands` as block arguments.
    `site` retains continuation identity and `resume_region` optionally selects
    the resumption region. Lowering preserves the selected wait and its
    continuation ABI.
  }];
  let arguments = !con(extraArgs, (ins Variadic<AnyType>:$continuation_operands,
                                      OptionalAttr<SimContinuationSiteAttr>:$site,
                                      OptionalAttr<SimEventRegion>:$resume_region));
  let successors = (successor AnySuccessor : $continuation);
  let hasVerifier = 1;
}
def NativeSuspendDelayOp : ScheduleNativeSuspendOp<"suspend.delay", (ins SimTimeType:$delay,
    OptionalAttr<SimTimingSiteAttr>:$timing)> {
  let summary = "suspend for a delay in design-precision ticks";
  let assemblyFormat = [{$delay `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)? attr-dict}];
}

def NativeSuspendChangeOp : ScheduleNativeSuspendOp<"suspend.change", (ins I64:$watched)> {
  let summary = "suspend until the value at a physical handle changes";
  let assemblyFormat = [{$watched `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)? attr-dict `:` type($watched)}];
}

def NativeSuspendEdgeOp : ScheduleNativeSuspendOp<"suspend.edge", (ins
    SimEdgeKind:$edge, I64:$watched)> {
  let summary = "suspend until a physical handle observes the requested edge";
  let assemblyFormat = [{$edge $watched `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict `:` type($watched)}];
}

def NativeSuspendEdgeIffOp : ScheduleNativeSuspendOp<"suspend.edge_iff", (ins
    SimEdgeKind:$edge, I64:$watched, I64:$condition)> {
  let summary = "suspend until a watched event whose level condition is true";
  let description = [{
    The condition is a directly addressable packed object. The scheduler
    samples its complete four-state value when the primary event occurs and
    latches a successful occurrence for the waiting process. Changes to the
    condition alone never resume the process. IEEE 1800 9.4.2.3 writes
    the primary event with an optional edge identifier -- its `always @(a iff
    enable == 1)` example qualifies a plain value change -- so a `change` edge
    is as ordinary here as a directed one.
  }];
  let assemblyFormat = [{$edge $watched `iff` $condition `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict `:` type($watched) `,` type($condition)}];
}

def NativeSuspendLevelOp : ScheduleNativeSuspendOp<"suspend.level", (ins I64:$watched)> {
  let summary = "suspend until a directly watched packed value becomes true";
  let description = [{
    The scheduler evaluates the complete four-state value after every
    overlapping store and latches the first true occurrence. This preserves a
    transient true value even if a later store changes it again before the
    waiting continuation executes.
  }];
  let assemblyFormat = [{$watched `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict `:` type($watched)}];
}

def NativeSuspendAnyOp : ScheduleNativeOp<"suspend.any", [
    Terminator,
    DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend until any watched handle observes its requested edge";
  // The edge inventory determines the watched prefix; the remaining values
  // are successor operands. Keeping one variadic group avoids a redundant
  // segment-size attribute in the persistent IR.
  let arguments = (ins Variadic<AnyType>:$values,
                       DenseI32ArrayAttr:$edges,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{$values `edges` $edges `to` $continuation
   attr-dict `:` type($values)}];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getWatched();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}

def NativeSuspendClockSetOp : ScheduleNativeOp<"suspend.clock_set", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend on an exact set of frozen clock occurrences";
  let description = [{
    The first `edges.size()` values are direct signal clock primaries. They are
    followed by `condition_count` optional iff handles and then successor
    operands. `condition_indices` contains -1 or the condition index for every
    primary. At most 64 primaries are accepted. The runtime groups all matched
    primaries from one exact scheduler publication wave into an occurrence
    mask without coalescing repeated occurrences in that wave.
    The optional `slot_final` marker is reserved for Clause 31 coordinators
    whose simultaneous-event decision needs every producer region at the
    current numeric simulation time. It changes scheduler admission only; the
    occurrence ABI and queue representation remain identical.
  }];
  let arguments = (ins Variadic<AnyType>:$values,
                       I32Attr:$condition_count,
                       DenseI32ArrayAttr:$edges,
                       DenseI32ArrayAttr:$condition_indices,
                       OptionalAttr<DenseI32ArrayAttr>:$condition_predicates,
                       I64Attr:$occurrence_site,
                       OptionalAttr<UnitAttr>:$slot_final,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{
    $values `conditions` $condition_count `edges` $edges
    `indices` $condition_indices `site` $occurrence_site
    `to` $continuation attr-dict `:` type($values)
  }];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getPrimaries();
    ::mlir::Operation::operand_range getConditions();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}

def NativeSuspendEventOp : ScheduleNativeSuspendOp<"suspend.event", (ins I64:$event)> {
  let summary = "suspend until a physical named-event handle is triggered";
  let assemblyFormat = [{$event `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)? attr-dict}];
}

def NativeSuspendEventOrderOp : ScheduleNativeOp<"suspend.event_order", [
    Terminator,
    DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend until named events occur in source order or fail";
  let description = [{
    The first `event_count` values are event handles in required occurrence
    order. Remaining values are successor operands. The scheduler observes
    every event publication synchronously, so an out-of-order occurrence is
    retained even when several events trigger before the continuation runs.
  }];
  let arguments = (ins Variadic<AnyType>:$values,
                       I32Attr:$event_count,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{$values `events` $event_count `to` $continuation
    attr-dict `:` type($values)}];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getEvents();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}

def NativeSuspendMailboxOp : ScheduleNativeSuspendOp<"suspend.mailbox", (
    ins I64:$mailbox, SimMailboxWaitKind:$kind)> {
  let summary = "suspend until a mailbox can complete a blocking operation";
  let description = [{
    Suspends on the mailbox's not-empty or not-full predicate. The mailbox
    must also be passed to the continuation, which keeps the managed handle in
    the canonical process frame and therefore rooted while the process waits.
  }];
  let assemblyFormat = [{$mailbox $kind `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict `:` type($mailbox)}];
  let hasVerifier = 1;
}

def NativeSuspendSemaphoreOp : ScheduleNativeSuspendOp<"suspend.semaphore", (
    ins I64:$semaphore, I32:$keys)> {
  let summary = "suspend for a FIFO semaphore acquisition";
  let description = [{
    Suspends until this waiter is at the head of the semaphore's FIFO wait
    order and the scheduler has atomically obtained the requested keys for it.
    The handle and key count are copied into the runtime wait record, which is
    a precise GC root and remains stable across suspension.
  }];
  let assemblyFormat = [{$keys `from` $semaphore `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict `:` type($semaphore)}];
  let hasVerifier = 1;
}

def NativeSuspendObserveOp : ScheduleNativeOp<"suspend.observe", [
    Terminator,
    DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend on source-ordered computed timing clauses";
  let description = [{
    Each primary observer has one encounter-time initial value and requested
    edge. `condition_indices` has one entry per primary: -1 denotes no `iff`,
    otherwise the entry indexes the condition observer list. Conditions are
    evaluated only after their corresponding primary occurrence.
  }];
  let arguments = (ins Variadic<AnyType>:$values,
                       I32Attr:$condition_count,
                       DenseI32ArrayAttr:$edges,
                       DenseI32ArrayAttr:$condition_indices,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{
    $values `conditions` $condition_count `edges` $edges
    `indices` $condition_indices `to` $continuation attr-dict
    `:` type($values)
  }];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getPrimaries();
    ::mlir::Operation::operand_range getInitialValues();
    ::mlir::Operation::operand_range getConditions();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}

def NativeSuspendForeverOp : ScheduleNativeSuspendOp<"suspend.forever"> {
  let summary = "permanently suspend the current logical process";
  let assemblyFormat = [{`to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict}];
}

def NativeSuspendAwaitOp : ScheduleNativeSuspendOp<"suspend.await", (ins I64:$process)> {
  let summary = "suspend until the awaited process terminates";
  let description = [{
    Resumes once the target process has finished, whether it terminated
    normally or was killed. This is used for an explicit task/process await;
    fork/join synchronization uses `suspend.join`.
  }];
  let assemblyFormat = [{$process `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)? attr-dict}];
}

def NativeSuspendJoinOp : ScheduleNativeOp<"suspend.join", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend until all or any child process terminates";
  // `process_count` determines the process prefix of `values`; the remainder
  // are successor operands. A single variadic group keeps segment bookkeeping
  // out of the persistent IR while still allowing the suspension-threading
  // pass to append live values.
  let arguments = (ins SimJoinKind:$kind, Variadic<AnyType>:$values,
                       I64Attr:$process_count,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{$kind $values `processes` $process_count `to`
    $continuation attr-dict `:` type($values)}];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getProcesses();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}

def NativeSuspendChildrenOp : ScheduleNativeOp<"suspend.children", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>,
                   MemWrite<SimProcessResource>]>
  ]> {
  let summary = "suspend until every current direct child has terminated";
  let arguments = (ins Variadic<AnyType>:$continuation_operands,
                       OptionalAttr<SimContinuationSiteAttr>:$site,
                       OptionalAttr<SimEventRegion>:$resume_region);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{`to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict}];
  let hasVerifier = 1;
}

def NativeSpawnOp : ScheduleNativeOp<"spawn", [
    CallOpInterface, DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    MemoryEffects<[MemWrite<SimSchedulerResource>, MemWrite<SimProcessResource>]>
  ]> {
  let summary = "spawn a sibling simulation process with explicit captures";
  let description = [{
    A spawn is a call edge that starts an independent logical process instead
    of executing in the caller. Its operands are the callee's entry captures;
    its result is the scheduler handle of the new process, not a callee result.
  }];
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$operands,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs);
  let results = (outs I64:$process);
  let assemblyFormat = [{$callee `(` $operands `)` attr-dict
    `:` type($operands) `->` qualified(type($process))}];
  let extraClassDeclaration = [{
    ::mlir::CallInterfaceCallable getCallableForCallee() { return getCalleeAttr(); }
    void setCalleeFromCallable(::mlir::CallInterfaceCallable callee) {
      setCalleeAttr(::llvm::cast<::mlir::FlatSymbolRefAttr>(
          ::llvm::cast<::mlir::SymbolRefAttr>(callee)));
    }
    ::mlir::Operation::operand_range getArgOperands() { return getOperands(); }
    ::mlir::MutableOperandRange getArgOperandsMutable() {
      return getOperandsMutable();
    }
  }];
  let hasVerifier = 1;
}

// Explicit projection at the semantic-context/native-ABI boundary.
def NativeContextOp : ScheduleNativeOp<"context", [Pure]> {
  let summary = "project a simulation context to its native runtime pointer";
  let arguments = (ins SimContextType:$context);
  let results = (outs LLVM_AnyPointer:$result);
  let assemblyFormat = "$context attr-dict `:` type($result)";
}
def NativeTimeOp : ScheduleNativeOp<"time", [Pure]> {
  let summary = "convert a simulation time value to native tick bits";
  let arguments = (ins SimTimeType:$time);
  let results = (outs I64:$result);
  let assemblyFormat = "$time attr-dict";
}
def NativeProcessControlOp : ScheduleNativeOp<"process.control", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemRead<SimSchedulerResource>,
                   MemWrite<SimSchedulerResource>,
                   MemRead<SimProcessResource>, MemWrite<SimProcessResource>]>
  ]> {
  let summary = "apply an IEEE control operation to one process object";
  let description = [{
    This is a control-flow terminator because the target can dynamically name
    the executing logical process or one of its ancestors. Resuming a process,
    or controlling another process while the caller survives, transfers
    immediately to the continuation. Suspending the caller yields and later
    resumes at that continuation. Killing the caller never reaches it.

    A null handle reports a runtime invalid-handle failure. Zero-time function
    entries may contain this operation; lowering must propagate its control
    action through the function call chain before coroutine or bytecode
    materialization.
  }];
  let arguments = (ins SimProcessControlKind:$kind,
                       I64:$process,
                       Variadic<AnyType>:$continuation_operands,
                       OptionalAttr<SimContinuationSiteAttr>:$site);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{$kind $process `to` $continuation
    (`(` $continuation_operands^ `:` type($continuation_operands) `)`)?
    attr-dict}];
  let hasVerifier = 1;
}
def NativeControlBoundaryOp : ScheduleNativeOp<"control.boundary", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    MemoryEffects<[MemWrite<SimProcessResource>]>
  ]> {
  let summary = "register the resumable exit of a named block activation";
  let description = [{
    The resume successor is the block exit used when another logical process
    disables this activation. Its operands are checkpointed in the canonical
    process frame. Ordinary execution registers that continuation and follows
    the body successor without yielding to the scheduler.
  }];
  let arguments = (ins I64:$activation,
                       Variadic<AnyType>:$resume_operands,
                       OptionalAttr<SimContinuationSiteAttr>:$site);
  let successors = (successor AnySuccessor:$resume,
                               AnySuccessor:$body);
  let assemblyFormat = [{$activation `resume` $resume
    (`(` $resume_operands^ `:` type($resume_operands) `)`)?
    `body` $body attr-dict}];
  let hasVerifier = 1;
}
def NativeTaskCallOp : ScheduleNativeOp<"task.call", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    MemoryEffects<[
      MemRead<SimStorageResource>, MemWrite<SimStorageResource>,
      MemRead<SimNetResource>, MemWrite<SimNetResource>,
      MemRead<SimSchedulerResource>, MemWrite<SimSchedulerResource>,
      MemRead<SimProcessResource>, MemWrite<SimProcessResource>,
      MemRead<SimHeapResource>, MemWrite<SimHeapResource>,
      MemRead<SimIOResource>, MemWrite<SimIOResource>,
      MemRead<SimRNGResource>, MemWrite<SimRNGResource>,
      MemRead<SimExternalResource>, MemWrite<SimExternalResource>
    ]>
  ]> {
  let summary = "transfer the current logical process into a task activation";
  let description = [{
    The argument prefix initializes the callee activation. The remaining
    operands are forwarded to the caller continuation after the task returns.
    Output destinations are explicit reference arguments in the callee
    signature, so a suspended task never retains native caller addresses.
  }];
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$values,
                       I64Attr:$argument_count,
                       OptionalAttr<SimContinuationSiteAttr>:$site);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{$callee `(` $values `)` `arguments`
    $argument_count `to` $continuation attr-dict `:` type($values)}];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getArguments();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}
def NativeClassVirtualTaskCallOp : ScheduleNativeOp<"class.virtual_task_call", [
    Terminator, DeclareOpInterfaceMethods<BranchOpInterface>,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    MemoryEffects<[
      MemRead<SimStorageResource>, MemWrite<SimStorageResource>,
      MemRead<SimNetResource>, MemWrite<SimNetResource>,
      MemRead<SimSchedulerResource>, MemWrite<SimSchedulerResource>,
      MemRead<SimProcessResource>, MemWrite<SimProcessResource>,
      MemRead<SimHeapResource>, MemWrite<SimHeapResource>,
      MemRead<SimIOResource>, MemWrite<SimIOResource>,
      MemRead<SimRNGResource>, MemWrite<SimRNGResource>,
      MemRead<SimExternalResource>, MemWrite<SimExternalResource>
    ]>
  ]> {
  let summary = "descriptor-dispatched virtual class task activation";
  let description = [{
    Resolves a virtual task through the receiver's managed class descriptor,
    then transfers the current logical process into the selected task
    activation. The receiver and explicit argument prefix initialize the
    method inputs after the implicit caller context; remaining values are
    forwarded to the continuation.
  }];
  let arguments = (ins I64:$receiver,
                       FlatSymbolRefAttr:$method,
                       I64Attr:$slot,
                       I64Attr:$signature_id,
                       Variadic<AnyType>:$values,
                       I64Attr:$argument_count,
                       OptionalAttr<SimContinuationSiteAttr>:$site);
  let successors = (successor AnySuccessor:$continuation);
  let assemblyFormat = [{
    $receiver `[` $method `]` `slot` $slot
    `signature_id` $signature_id
    `(` $values `)` `arguments` $argument_count `to` $continuation
    attr-dict `:` functional-type(operands, results)
  }];
  let extraClassDeclaration = [{
    ::mlir::Operation::operand_range getArguments();
    ::mlir::Operation::operand_range getContinuationOperands();
    ::mlir::MutableOperandRange getContinuationOperandsMutable();
  }];
  let hasVerifier = 1;
}
def NativeExecuteOp : ScheduleNativeOp<"execute", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "invoke a scheduled body through its prepared native ABI";
  let arguments = (ins SymbolRefAttr:$callee, Variadic<AnyType>:$operands,
                       OptionalAttr<UnitAttr>:$status_result);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = "$callee `(` $operands `)` attr-dict `:` functional-type($operands, $results)";
}

def NativeSynchronousClassCallOp : ScheduleNativeOp<"class.synchronous_call", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "invoke a proven non-suspending virtual task through its native table";
  let description = [{
    Compiler-only task call inside an ordinary native body. Admission proves
    that every possible target returns without suspension; the task's original
    activation entry remains available independently for fallback execution.
  }];
  let arguments = (ins AnyType:$receiver, FlatSymbolRefAttr:$method,
                       I64Attr:$slot, I64Attr:$signature_id,
                       Variadic<AnyType>:$arguments);
  let assemblyFormat = [{
    $receiver `[` $method `]` `slot` $slot `signature_id` $signature_id
    `(` $arguments `)` attr-dict `:` type($receiver)
    (`,` type($arguments)^)?
  }];
}

def NativeMethodOp : ScheduleNativeOp<"class.method", [
    Symbol, DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    MemoryEffects<[MemWrite<SimInventoryResource>]>
  ]> {
  let summary = "class method signature and deterministic dispatch slot";
  let arguments = (ins
    SymbolNameAttr:$sym_name,
    FlatSymbolRefAttr:$owner,
    TypeAttr:$function_type,
    OptionalAttr<TypeAttr>:$native_type,
    OptionalAttr<I64Attr>:$slot,
    OptionalAttr<I64Attr>:$signature_id,
    OptionalAttr<I64Attr>:$interface_ordinal,
    OptionalAttr<FlatSymbolRefAttr>:$implementation,
    BoolAttr:$is_virtual,
    BoolAttr:$is_pure,
    BoolAttr:$is_static,
    BoolAttr:$is_task,
    BoolAttr:$is_final,
    OptionalAttr<StrAttr>:$debug_name
  );
  let assemblyFormat = [{
    $sym_name `of` $owner (`slot` $slot^)?
    (`signature_id` $signature_id^)?
    (`interface_ordinal` $interface_ordinal^)?
    (`implemented_by` $implementation^)? `:` $function_type attr-dict
  }];
  let hasVerifier = 1;
}

def NativeObserverOp : ScheduleNativeOp<"observer", [Pure]> {
  let summary = "computed observer descriptor with physical captures";
  let arguments = (ins Variadic<AnyType>:$values, I64Attr:$capture_count);
  let results = (outs I64:$token);
  let assemblyFormat = [{
    `(` ($values^ `:` type($values))? `)` `captures` $capture_count attr-dict
  }];
  let hasVerifier = 1;
}
def NativeScratchOp : ScheduleNativeOp<"scratch", [MemoryEffects<[MemAlloc]>]> {
  let summary = "native activation scratch storage that survives status branches";
  let arguments = (ins I64Attr:$size);
  let results = (outs RTMutableByteSpanType:$result);
  let assemblyFormat = "$size attr-dict";
  let hasVerifier = 1;
}
// Native design state lives in two byte planes, the values and the X/Z bits
// beside them (IEEE 1800-2023 6.3.1). These operations name the plane they
// access, so native passes recognize state accesses by operation rather than
// by tracing addresses to the planes' globals. Each refers to its plane's
// global so symbol-use queries still see it, and may only appear in a
// function. Accesses are neither volatile nor atomic. finalize-native-functions
// lowers them to the LLVM accesses they stand for.
//
// What native passes need to know about an access is a property:
// - window: the conservative physical bytes [begin, end) a bounds-checked
//   access with a dynamic offset may touch, including its packing padding;
// - written_bits (stores): for a store whose byte address is dynamic, the
//   canonical bits [begin, begin + width) its mask can change, as
//   [begin, width];
// - latch_destination: the access reads or writes the destination of a
//   per-site NBA latch, whose unknown bits fixed-root proofs do not cover, so
//   the fast two-state NBA commit keeps it;
// - summary_reported (stores): the writer reports the roots this store
//   changes to the unknown summary itself;
// - owner: the activation-group member whose activation performs the access.
def StateAccessValue : AnyTypeOf<[AnySignlessInteger,
                                  VectorOfAnyRankOf<[AnySignlessInteger]>]>;

def NativeStateAddressOp : ScheduleNativeOp<"state.address", [
    Pure, ConstantLike, DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "base address of a canonical native state plane";
  let description = [{
    The address of the first byte of a state plane, for a plane that leaves
    typed state operations whole: into runtime calls and bulk copies. Like
    `llvm.mlir.addressof`, it is a constant; it folds to its plane.
  }];
  let arguments = (ins FlatSymbolRefAttr:$global);
  let results = (outs LLVM_DefaultPointer:$result);
  let assemblyFormat = "$global attr-dict `:` qualified(type($result))";
  let builders = [OpBuilder<(ins "::talos::schedule::StatePlane":$plane)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

def NativeStateWindowAddressOp : ScheduleNativeOp<"state.window_address", [
    Pure, DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "address of a window of a native state plane";
  let description = [{
    The address of the plane's byte at `static_offset` plus the optional
    `dynamic_offset`, for a window whose bytes leave typed state operations:
    bulk copies and fills, runtime calls, and memory values that borrow
    state in place. Loads and stores of the window are `schedule.state.load`
    and `schedule.state.store` at its offset; native finalization rejects an
    LLVM load, store or address computation on this address, so every
    pointer into a plane is this operation or `schedule.state.address`.

    A contribution plane is reached through the pointer its global binds;
    scheduler main has the runtime bind it once, before any design code
    runs, so the address is still a pure function of its operands.
  }];
  let arguments = (ins FlatSymbolRefAttr:$global,
                       Optional<I64>:$dynamic_offset,
                       I64Attr:$static_offset);
  let results = (outs LLVM_DefaultPointer:$result);
  let assemblyFormat = [{
    $global `[` custom<StateOffset>($dynamic_offset, $static_offset) `]`
    attr-dict `:` qualified(type($result))
  }];
  let builders = [OpBuilder<(ins "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$dynamicOffset,
                                 "uint64_t":$staticOffset)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
    /// The byte offset when it is constant: the static offset, plus a
    /// dynamic one defined by a constant.
    std::optional<uint64_t> getConstantOffset();
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

def NativeStateLoadOp : ScheduleNativeOp<"state.load", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read a window of a native state plane";
  let description = [{
    Reads the bytes of the plane starting at byte `static_offset` plus the
    optional `dynamic_offset` as one value, with the given alignment.
  }];
  let arguments = (ins Arg<FlatSymbolRefAttr, "the plane's global",
                           [MemRead]>:$global,
                       Optional<I64>:$dynamic_offset,
                       I64Attr:$static_offset,
                       IntValidAlignment<I64Attr>:$alignment,
                       OptionalAttr<DenseI64ArrayAttr>:$window,
                       UnitAttr:$latch_destination,
                       OptionalAttr<I32Attr>:$owner);
  let results = (outs StateAccessValue:$result);
  let assemblyFormat = [{
    $global `[` custom<StateOffset>($dynamic_offset, $static_offset) `]`
    attr-dict `:` type($result)
  }];
  let builders = [OpBuilder<(ins "::mlir::Type":$type,
                                 "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$dynamicOffset,
                                 "uint64_t":$staticOffset,
                                 "uint64_t":$alignment)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
    /// The byte offset when it is constant: the static offset, plus a
    /// dynamic one defined by a constant.
    std::optional<uint64_t> getConstantOffset();
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

def NativeStateStoreOp : ScheduleNativeOp<"state.store", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write a window of a native state plane";
  let description = [{
    Writes `value` to the bytes of the plane starting at byte `static_offset`
    plus the optional `dynamic_offset`, with the given alignment.
  }];
  let arguments = (ins StateAccessValue:$value,
                       Arg<FlatSymbolRefAttr, "the plane's global",
                           [MemWrite]>:$global,
                       Optional<I64>:$dynamic_offset,
                       I64Attr:$static_offset,
                       IntValidAlignment<I64Attr>:$alignment,
                       OptionalAttr<DenseI64ArrayAttr>:$window,
                       OptionalAttr<DenseI64ArrayAttr>:$written_bits,
                       UnitAttr:$latch_destination,
                       UnitAttr:$summary_reported,
                       OptionalAttr<I32Attr>:$owner);
  let assemblyFormat = [{
    $value `,` $global `[` custom<StateOffset>($dynamic_offset, $static_offset)
    `]` attr-dict `:` type($value)
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value,
                                 "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$dynamicOffset,
                                 "uint64_t":$staticOffset,
                                 "uint64_t":$alignment)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
    /// The byte offset when it is constant: the static offset, plus a
    /// dynamic one defined by a constant.
    std::optional<uint64_t> getConstantOffset();
  }];
  let hasFolder = 1;
  let hasVerifier = 1;
}

// Generated NBA accumulator records (talos_rt_generated_nba_accumulator_256).
// A generated stage writes a record's fields, the NBA barrier commits and
// clears them, and the runtime consumes records it is handed at its own
// barrier (IEEE 1800-2023 4.9.4, 10.4.2). Native passes prove which captures
// are private to a generated barrier by seeing every access to a record, so
// the fields are accessed only through the typed operations below. Their
// physical layout is chosen when they are lowered: a two-state executable's
// record has no X/Z field.
def NativeNBAAccumulatorAddressOp : ScheduleNativeOp<"nba.acc.address", [
    Pure, DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "address of a generated NBA accumulator record";
  let description = [{
    The address of the generated NBA accumulator record `global`. Its fields
    are read and written by `schedule.nba.acc.load` and
    `schedule.nba.acc.store`; native finalization rejects any other use of
    this address.
  }];
  let arguments = (ins FlatSymbolRefAttr:$global);
  let results = (outs LLVM_DefaultPointer:$result);
  let assemblyFormat = "$global attr-dict `:` qualified(type($result))";
  let builders = [OpBuilder<(ins "::llvm::StringRef":$global)>];
  let hasVerifier = 1;
}

def NativeNBAAccumulatorLoadOp : ScheduleNativeOp<"nba.acc.load"> {
  let summary = "read a field of a generated NBA accumulator record";
  let description = [{
    Reads the bytes of `field` of the accumulator record at `record`, from
    byte `offset` within the field, as one value with the given alignment.
    The record is a `schedule.nba.acc.address` or a record pointer read from
    a table of records.

    - `pending_root`: a read of `valid` by the generated consumer that commits
      this root, testing whether its capture is still pending. A transaction
      that keeps the root's captures private answers it from its own index.
    - `at_commit`: a read of `write_mask` by the barrier that commits the
      capture, after it claimed the root's dirty bit; not a test for a new
      stage.
    - `owner`: the activation-group member whose activation performs the
      access.
  }];
  let arguments = (ins Arg<LLVM_DefaultPointer, "the record", [MemRead]>:$record,
                       NBAAccumulatorFieldEnum:$field,
                       DefaultValuedAttr<I64Attr, "0">:$offset,
                       IntValidAlignment<I64Attr>:$alignment,
                       OptionalAttr<I32Attr>:$pending_root,
                       UnitAttr:$at_commit,
                       OptionalAttr<I32Attr>:$owner);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = [{
    $record `[` custom<AccumulatorField>($field, $offset) `]` attr-dict `:`
    type($result)
  }];
  let builders = [OpBuilder<(ins "::mlir::Type":$type, "::mlir::Value":$record,
                                 "::talos::schedule::NBAAccumulatorField":$field,
                                 "uint64_t":$offset, "uint64_t":$alignment)>];
  let hasVerifier = 1;
}

def NativeNBAAccumulatorStoreOp : ScheduleNativeOp<"nba.acc.store"> {
  let summary = "write a field of a generated NBA accumulator record";
  let description = [{
    Writes `value` to the bytes of `field` of the accumulator record at
    `record`, from byte `offset` within the field, with the given alignment.
    `owner` is the activation-group member whose activation performs it.
  }];
  let arguments = (ins AnySignlessInteger:$value,
                       Arg<LLVM_DefaultPointer, "the record", [MemWrite]>:$record,
                       NBAAccumulatorFieldEnum:$field,
                       DefaultValuedAttr<I64Attr, "0">:$offset,
                       IntValidAlignment<I64Attr>:$alignment,
                       OptionalAttr<I32Attr>:$owner);
  let assemblyFormat = [{
    $value `,` $record `[` custom<AccumulatorField>($field, $offset) `]`
    attr-dict `:` type($value)
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value, "::mlir::Value":$record,
                                 "::talos::schedule::NBAAccumulatorField":$field,
                                 "uint64_t":$offset, "uint64_t":$alignment)>];
  let hasVerifier = 1;
}

// The NBA readiness index (NBAIndex): words of the dirty-root and summary
// globals, read and written whole. Native passes that keep a root's captures
// private to a generated barrier rewrite that root's index accesses, so the
// index is accessed only through these operations in functions.
//
// What native passes need to know about an access is a property:
// - root: the access is root `root`'s own: the dirty word holding its bit or
//   the summary word holding its dirty word's bit, read to test or written to
//   mark the root's pending capture;
// - canonical_capture: with `root`, the capture's payload is held where the
//   runtime commits it (a runtime-routed or fixed-slot capture), so the root
//   stays in the canonical index;
// - capture (stores): the certified target of the generated capture the
//   store marks: root, static state, width, mask, commit region and source
//   site;
// - owner: the activation-group member whose activation performs the access.
def NativeNBAIndexLoadOp : ScheduleNativeOp<"nba.index.load", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read a word of the NBA readiness index";
  let description = [{
    Reads the 64-bit word `static_word` plus the optional `dynamic_word` of
    the NBA readiness index `global`.
  }];
  let arguments = (ins Arg<FlatSymbolRefAttr, "the index's global",
                           [MemRead]>:$global,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$root,
                       UnitAttr:$canonical_capture,
                       OptionalAttr<I32Attr>:$owner);
  let results = (outs I64:$result);
  let assemblyFormat = [{
    $global `[` custom<StateOffset>($dynamic_word, $static_word) `]` attr-dict
  }];
  let builders = [OpBuilder<(ins "::talos::schedule::NBAIndex":$index,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::NBAIndex getIndex();
  }];
  let hasVerifier = 1;
}

def NativeNBAIndexStoreOp : ScheduleNativeOp<"nba.index.store", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write a word of the NBA readiness index";
  let description = [{
    Writes `value` to the 64-bit word `static_word` plus the optional
    `dynamic_word` of the NBA readiness index `global`.
  }];
  let arguments = (ins I64:$value,
                       Arg<FlatSymbolRefAttr, "the index's global",
                           [MemWrite]>:$global,
                       Optional<I64>:$dynamic_word,
                       I64Attr:$static_word,
                       OptionalAttr<I32Attr>:$root,
                       UnitAttr:$canonical_capture,
                       OptionalAttr<DenseI64ArrayAttr>:$capture,
                       OptionalAttr<I32Attr>:$owner);
  let assemblyFormat = [{
    $value `,` $global `[` custom<StateOffset>($dynamic_word, $static_word)
    `]` attr-dict
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value,
                                 "::talos::schedule::NBAIndex":$index,
                                 "::mlir::Value":$dynamicWord,
                                 "uint64_t":$staticWord)>];
  let extraClassDeclaration = [{
    ::talos::schedule::NBAIndex getIndex();
  }];
  let hasVerifier = 1;
}

def NativeNBAStageOp : ScheduleNativeOp<"nba.stage"> {
  let summary = "stage a nonblocking assignment at a static NBA site";
  let description = [{
    Stages the update of a nonblocking assignment at static NBA site `site`
    for the runtime context `runtime_context`:
    `width` bits of the RHS that `value` points to, with the X/Z bits that
    `unknown` points to when the RHS has any, for the destination `handle`
    in the state of `state_bits` bits. The RHS and the destination were
    evaluated when the assignment executed; the update is applied in the NBA
    region (IEEE 1800-2023 4.9.4, 10.4.2).

    Native lowering emits this for the runtime's static NBA entry. AOT
    materialization replaces it with generated staging where it can; any
    other becomes the runtime call and its failure check. Its memory
    effects are those of that runtime call.
  }];
  let arguments = (ins LLVM_DefaultPointer:$runtime_context, I64:$handle,
                       LLVM_DefaultPointer:$value,
                       Optional<LLVM_DefaultPointer>:$unknown,
                       I64Attr:$site, I64Attr:$state_bits, I64Attr:$width);
  let assemblyFormat = [{
    $runtime_context `,` $handle `,` $value (`,` $unknown^)? attr-dict
  }];
  let hasVerifier = 1;
}

// Stable native state handles (talos_rt_stable_handle_v1, Runtime
// StableHandle.h). A handle encodes a state object and a bit offset in it;
// the invalid handle UINT64_MAX names no storage. An index that is out of
// bounds or has X/Z bits is invalid: a read through the invalid handle yields
// the invalid-index value and a write through it does nothing
// (IEEE 1800-2023 7.4.5, 11.5.1, 11.5.2). A selection is a chain of these
// operations above a root handle.
def NativeHandleOffsetOp : ScheduleNativeOp<"handle.offset", [Pure]> {
  let summary = "offset a stable native state handle";
  let description = [{
    The handle of the bit `amount` (signed) bits after the one `handle`
    names: the runtime's `talos_rt_stable_handle_offset`, a total function
    that never traps. `handle` is a native reference: a stable handle as the
    runtime encodes it, or the invalid handle. The result is the invalid
    handle when `handle` is invalid, when the new offset overflows, or when
    it is not representable for the handle's kind (a global offset must lie
    in [0, 2^61), a static or automatic one in the signed 32-bit range; a
    negative static offset is kept for a part-select that only partly
    overlaps its object, 11.5.1).

    `in_bounds` records the compiler's proof that `handle` is valid and that
    its offset and the new offset both lie in [0, INT32_MAX]; the offset
    field then neither carries nor borrows, so the result is the plain sum
    `handle + amount`.

    Being a total function of its operands, it is pure: it reads and writes
    no state and has no failure to preserve, since an invalid selection is
    the invalid-handle result that its readers and writers handle (IEEE
    1800-2023 7.4.5, 11.5.1).

    An offset by zero is `handle` itself: the runtime re-encodes a stable
    handle unchanged and keeps the invalid handle. An offset proved in
    bounds of one proved in bounds is one offset by the sum of the amounts,
    proved in bounds: its handle is valid and the final offset in range. An
    offset of one not proved in bounds stays separate, since the runtime
    checks that each step is representable. Like the runtime call it stands
    for, it does not fold constant operands: producers offset those when
    they create the selection.

    Native lowering creates it; it becomes the runtime call, or the sum when
    `in_bounds`, once AOT planning has read the selections it is part of.
  }];
  let arguments = (ins I64:$handle, I64:$amount, UnitAttr:$in_bounds);
  let results = (outs I64:$result);
  let assemblyFormat = [{
    $handle `,` $amount (`in_bounds` $in_bounds^)? attr-dict
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$handle,
                                 "::mlir::Value":$amount,
                                 CArg<"bool", "false">:$inBounds), [{
    build($_builder, $_state, $_builder.getI64Type(), handle, amount,
          inBounds);
  }]>];
  let hasFolder = 1;
  let hasCanonicalizer = 1;
}

def NativeHandleGuardOp : ScheduleNativeOp<"handle.guard", [Pure]> {
  let summary = "select a stable native state handle or the invalid handle";
  let description = [{
    `handle` when `valid` holds, otherwise the invalid handle UINT64_MAX:
    `valid` is the validity of the selection that produced `handle`, e.g.
    its index being in range and free of X/Z bits (IEEE 1800-2023 7.4.5,
    11.5.1).

    It folds as the select of `handle` and an invalid-handle constant that
    it becomes once AOT planning has read the selection.
  }];
  let arguments = (ins I1:$valid, I64:$handle);
  let results = (outs I64:$result);
  let assemblyFormat = "$valid `,` $handle attr-dict";
  let builders = [OpBuilder<(ins "::mlir::Value":$valid,
                                 "::mlir::Value":$handle), [{
    build($_builder, $_state, $_builder.getI64Type(), valid, handle);
  }]>];
  let hasFolder = 1;
}

// Accesses of the state a stable handle names, for state native code cannot
// address itself: a dynamic selection the compiler did not bound, an
// automatic variable, or a root that a force or procedural continuous
// assignment may hold. The runtime resolves the handle and chooses at run
// time which image it reads or writes, so these stand for its calls and,
// like them, have unknown memory effects. Each names the plane it accesses
// by its global, like the other state operations. A scalar access moves an
// SSA value; a `_bytes` access moves `width` bits through a byte buffer:
// little endian, ceil(width / 8) bytes, the padding bits of the last byte
// zero. `state_bits` is the size of the design state.
//
// Native lowering creates them; once AOT planning has read the eval bodies'
// accesses, they become the runtime calls, a scalar access passing its value
// through a temporary.
def NativeStateLoadHandleOp : ScheduleNativeOp<"state.load_handle", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read the native state a stable handle names";
  let description = [{
    The bits of the plane at the state `handle` names, as many as the result
    has. A bit the handle does not name reads as X, the value of an invalid
    index: every bit through the invalid handle, and the bits of a selection
    outside its object (IEEE 1800-2023 7.4.5, 11.5.1). X is 0 in the value
    plane and 1 in the unknown plane. A two-state executable reads 0 from the
    unknown plane.

    It stands for the runtime's `talos_rt_v1_native_state_load_plane`.
  }];
  let arguments = (ins FlatSymbolRefAttr:$global, I64:$handle,
                       I64Attr:$state_bits);
  let results = (outs AnySignlessInteger:$result);
  let assemblyFormat = [{
    $global `[` $handle `]` attr-dict `:` type($result)
  }];
  let builders = [OpBuilder<(ins "::mlir::Type":$type,
                                 "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$handle,
                                 "uint64_t":$stateBits)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
    /// The number of bits the read moves.
    uint64_t getWidth() { return getType().getIntOrFloatBitWidth(); }
  }];
  let hasVerifier = 1;
}

def NativeStateLoadHandleBytesOp
    : ScheduleNativeOp<"state.load_handle_bytes", [
          DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "read the native state a stable handle names into a buffer";
  let description = [{
    Writes the `width` bits of the plane at the state `handle` names to the
    buffer at `buffer`, with the bits a scalar `schedule.state.load_handle`
    reads.
  }];
  let arguments = (ins FlatSymbolRefAttr:$global, I64:$handle,
                       LLVM_DefaultPointer:$buffer, I64Attr:$state_bits,
                       I64Attr:$width);
  let assemblyFormat = [{
    $global `[` $handle `]` `into` $buffer attr-dict
  }];
  let builders = [OpBuilder<(ins "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$handle,
                                 "::mlir::Value":$buffer,
                                 "uint64_t":$stateBits, "uint64_t":$width)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
  }];
  let hasVerifier = 1;
}

def NativeStateStoreHandleOp : ScheduleNativeOp<"state.store_handle", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write the native state a stable handle names";
  let description = [{
    Writes `value` to the plane at the state `handle` names, and returns
    whether any of its bits changed: one change for the whole write, as an
    event sees it (IEEE 1800-2023 9.4.2). A bit the handle does not name is
    not written: nothing through the invalid handle, and only the bits inside
    its object of a selection partly outside it (7.4.5, 11.5.1). A bit that
    a force or procedural continuous assignment holds keeps its value
    (10.6). `continuous` marks a continuous assignment's contribution, which
    the runtime also keeps for a later release (10.6.2). A two-state
    executable writes nothing to the unknown plane.

    It stands for the runtime's `talos_rt_v1_native_state_store_plane`, or
    `talos_rt_v1_native_state_store_continuous_plane` with `continuous`.
  }];
  let arguments = (ins AnySignlessInteger:$value, FlatSymbolRefAttr:$global,
                       I64:$handle, I64Attr:$state_bits,
                       UnitAttr:$continuous);
  let results = (outs I1:$changed);
  let assemblyFormat = [{
    $value `,` $global `[` $handle `]` (`continuous` $continuous^)? attr-dict
    `:` type($value)
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$value,
                                 "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$handle,
                                 "uint64_t":$stateBits, "bool":$continuous)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
    /// The number of bits the write moves.
    uint64_t getWidth() {
      return getValue().getType().getIntOrFloatBitWidth();
    }
  }];
  let hasVerifier = 1;
}

def NativeStateStoreHandleBytesOp
    : ScheduleNativeOp<"state.store_handle_bytes", [
          DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "write the native state a stable handle names from a buffer";
  let description = [{
    Writes the `width` bits of the buffer at `buffer` as a scalar
    `schedule.state.store_handle` writes its value, and sets the byte at
    `changed` to whether any of them changed.
  }];
  let arguments = (ins LLVM_DefaultPointer:$buffer, FlatSymbolRefAttr:$global,
                       I64:$handle, LLVM_DefaultPointer:$changed,
                       I64Attr:$state_bits, I64Attr:$width,
                       UnitAttr:$continuous);
  let assemblyFormat = [{
    $buffer `,` $global `[` $handle `]` `changed` $changed
    (`continuous` $continuous^)? attr-dict
  }];
  let builders = [OpBuilder<(ins "::mlir::Value":$buffer,
                                 "::talos::schedule::StatePlane":$plane,
                                 "::mlir::Value":$handle,
                                 "::mlir::Value":$changed,
                                 "uint64_t":$stateBits, "uint64_t":$width,
                                 "bool":$continuous)>];
  let extraClassDeclaration = [{
    ::talos::schedule::StatePlane getPlane();
  }];
  let hasVerifier = 1;
}

def NativeStateFrameStoreOp : ScheduleNativeOp<"state.frame_store"> {
  let summary = "write and publish the native state a stable handle names";
  let description = [{
    The executing process's complete packed blocking write of `value`, at
    most 64 bits, to the state `handle` names: with `four_state`, `unknown`
    holds its X/Z bits (none when absent), and both planes change before the
    one value-change publication of the write (IEEE 1800-2023 9.4.2). A bit
    that a force or procedural continuous assignment holds keeps its value
    (10.6); `continuous` marks a continuous assignment's contribution, which
    the runtime also keeps for a later release (10.6.2). `state_bits` is the
    size of the design state.

    It stands for the runtime's `talos_rt_v1_native_frame_store`, which
    publishes in place when it can and otherwise falls back to the generic
    handle-addressed store and transition; like that call it has unknown
    memory effects. Native lowering creates it; it becomes the call once AOT
    planning has read the eval bodies' accesses.
  }];
  let arguments = (ins AnySignlessInteger:$value,
                       Optional<AnySignlessInteger>:$unknown, I64:$handle,
                       I64Attr:$state_bits, UnitAttr:$four_state,
                       UnitAttr:$continuous);
  let assemblyFormat = [{
    $value (`,` $unknown^)? `to` $handle (`four_state` $four_state^)?
    (`continuous` $continuous^)? attr-dict `:` type($value)
    (`,` type($unknown)^)?
  }];
  let hasVerifier = 1;
}

// A DPI export thunk copies an exported task's output formals, automatic
// variables, to its foreign caller's arguments when the task returns
// (IEEE 1800-2023 35.6.1, 35.8).
def NativeStateLoadAutomaticOp : ScheduleNativeOp<"state.load_automatic"> {
  let summary = "read an automatic variable a stable handle names";
  let description = [{
    Writes the `width` bits of the automatic variable `handle` names, its
    value or with `unknown` its X/Z bits, to the buffer at `buffer` for the
    runtime context `runtime_context`, and returns the runtime status: an
    error when the variable no longer exists. A bit outside the variable
    reads 0. The buffer is little endian, ceil(width / 8) bytes, the padding
    bits of the last byte zero.

    It stands for the runtime's `talos_rt_v1_native_state_load_plane` on no
    design state, and has the unknown memory effects of that call.
  }];
  let arguments = (ins LLVM_DefaultPointer:$runtime_context, I64:$handle,
                       LLVM_DefaultPointer:$buffer, I64Attr:$width,
                       UnitAttr:$unknown);
  let results = (outs I32:$status);
  let assemblyFormat = [{
    $runtime_context `,` $handle `into` $buffer (`unknown` $unknown^)?
    attr-dict
  }];
  let hasVerifier = 1;
}

def NativeByteAddressOp : ScheduleNativeOp<"bytes.address", [Pure]> {
  let summary = "immutable bytes awaiting executable reachability";
  let arguments = (ins StrAttr:$name, StrAttr:$value, I64Attr:$alignment);
  let results = (outs LLVM_AnyPointer:$result);
  let assemblyFormat = [{
    $name `=` $value `alignment` $alignment attr-dict `:` qualified(type($result))
  }];
}
// Activation-local root records are lowered only after simulation design
// symbol tables have been flattened into the native module. A `lazy` push
// registers the record only when it is not registered yet (its runtime cookie
// is zero) and otherwise reports success, so an activation registers its roots
// at the first collection point it reaches instead of on entry.
def NativeManagedRootPushOp : ScheduleNativeOp<"gc.root_range.push", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimProcessResource>,
                   MemWrite<SimHeapResource>]>
  ]> {
  let summary = "register an activation-local managed root range";
  let description = [{
    Registers the activation's root record and slot range with the runtime.
    With `lazy`, a record whose runtime cookie is already nonzero remains
    registered and the operation reports success. Registration is paired with
    `schedule.gc.root_range.pop` before the activation releases its storage.
  }];
  let arguments = (ins LLVM_AnyPointer:$record, LLVM_AnyPointer:$slots,
                       I64:$count, UnitAttr:$lazy);
  let results = (outs I32:$status);
  let assemblyFormat = [{
    $record `slots` $slots `count` $count (`lazy` $lazy^)? attr-dict `:`
    qualified(type($record)) `,` qualified(type($slots))
  }];
}
// The startup and shutdown steps a generated scheduler main runs around the
// root spawn when the executable synchronizes its native state with the
// canonical image or hosts VPI. Main lowering places them; the driver lowers
// them to runtime calls after its last module-level rewrites, when it knows
// the VPI startup libraries.
def NativeLifecycleStartOp : ScheduleNativeOp<"lifecycle.start", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimSchedulerResource>,
                   MemWrite<SimSchedulerResource>, MemWrite<SimStorageResource>]>
  ]> {
  let summary = "run the startup steps before the root process spawns";
  let description = [{
    In order:
    - with `state_sync`: copy the canonical image's `state_bits` bits into the
      native state planes;
    - with `resolve_initial_drivers`: resolve the initial driver values;
    - with `vpi`: run the vlog_startup_routines of the VPI startup libraries,
      then the cbEndOfCompile and cbStartOfSimulation callbacks (IEEE
      1800-2023 36.9.1, 36.10.2, 38.36.3).
    Each step fails the scheduler with its status.
  }];
  let arguments = (ins I64Attr:$state_bits, UnitAttr:$state_sync,
                       UnitAttr:$resolve_initial_drivers, UnitAttr:$vpi);
  let assemblyFormat = [{
    `state_bits` $state_bits (`state_sync` $state_sync^)?
    (`resolve_initial_drivers` $resolve_initial_drivers^)? (`vpi` $vpi^)?
    attr-dict
  }];
}
def NativeLifecycleFinishOp : ScheduleNativeOp<"lifecycle.finish", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimSchedulerResource>,
                   MemWrite<SimSchedulerResource>]>
  ]> {
  let summary = "run the VPI end-of-simulation callbacks";
  let description = [{
    Runs the cbEndOfSimulation callbacks (IEEE 1800-2023 38.36.3). The result
    is `status` when it reports a failure, else the callbacks' status.
  }];
  let arguments = (ins LLVM_AnyPointer:$context, I32:$status);
  let results = (outs I32:$result);
}
def NativeLifecycleShutdownOp : ScheduleNativeOp<"lifecycle.shutdown", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimSchedulerResource>,
                   MemWrite<SimSchedulerResource>]>
  ]> {
  let summary = "release the VPI session before the context is destroyed";
  let arguments = (ins LLVM_AnyPointer:$context);
}
// A designated managed-heap collection point. Generated schedules place
// these where no activation is running, such as between time slots, and the
// runtime then reclaims deferred allocation pressure only here (IEEE
// 1800 8.29 leaves the timing of reclamation to the implementation).
// Points that follow an edge of a proven periodic clock record the clock, its
// period and the edge, so they can be thinned to one collection per cycle;
// `edge` then holds whether that edge occurred in the current slot. A point
// that does not run reports success.
def NativeGCCollectOp : ScheduleNativeOp<"gc.collect", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimHeapResource>,
                   MemWrite<SimHeapResource>]>
  ]> {
  let summary = "designated managed-heap collection point";
  let description = [{
    Collects deferred allocation pressure at a designated scheduler boundary
    where no activation is executing. An optional edge predicate gates the
    collection. Periodic-clock metadata allows scheduling passes to retain
    one collection per proven clock cycle. A skipped collection reports
    success. IEEE 1800 8.29 leaves reclamation timing to the implementation.
  }];
  let arguments = (ins LLVM_AnyPointer:$runtime_context, Optional<I1>:$edge,
                       OptionalAttr<I32Attr>:$periodic_clock,
                       OptionalAttr<I64Attr>:$period,
                       UnitAttr:$posedge);
  let results = (outs I32:$status);
  let assemblyFormat = [{
    $runtime_context (`if` $edge^)? attr-dict `:`
    qualified(type($runtime_context))
  }];
  let hasVerifier = 1;
}
// Unregisters a record if it is registered; a lazily pushed record may not be.
def NativeManagedRootPopOp : ScheduleNativeOp<"gc.root_range.pop", [
    MemoryEffects<[MemRead, MemWrite, MemRead<SimProcessResource>,
                   MemWrite<SimHeapResource>]>
  ]> {
  let summary = "unregister an activation-local managed root range";
  let description = [{
    Unregisters the record if it is registered. This also accepts a record
    whose lazy push never ran, so cleanup can follow a common activation exit.
  }];
  let arguments = (ins LLVM_AnyPointer:$record);
  let assemblyFormat = "$record attr-dict `:` qualified(type($record))";
}
#endif
