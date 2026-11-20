// One schema for scheduling metadata keys and their MLIR payload types.
// Field names are generated from this schema; consumers use the typed enum.
class ScheduleField<string name, string wire, string type> {
  string cppName = name;
  string wireName = wire;
  string attributeType = type;
}
// Source actors, in the exact chosen run order, between an interrupted actor's
// prefix and continuation. Shared native/bytecode rank analysis preserves this
// phase order, including the original actor's first run and final re-arm.
def ActivePreemptionAfter : ScheduleField<"ActivePreemptionAfter", "schedule.active_preemption_after",
    "::mlir::ArrayAttr">;
// General source interleavings distinguish runs of the same actor. Every
// handoff carries the complete ordered actor list and its continuation's
// index into that list, including virtual re-arms. References remain ordinary
// function symbols; no transformation-owned operation identity escapes.
def ActivePreemptionRuns : ScheduleField<"ActivePreemptionRuns", "schedule.active_preemption_runs",
    "::mlir::ArrayAttr">;
def ActivePreemptionResume : ScheduleField<"ActivePreemptionResume", "schedule.active_preemption_resume",
    "::mlir::IntegerAttr">;
// The handoff follows the actor's complete body and precedes only its
// original event control (a virtual re-arm). The body runs atomically, so no
// partial publication is exposed and no prefix-input proof is required.
def ActivePreemptionRearm : ScheduleField<"ActivePreemptionRearm", "schedule.active_preemption_rearm",
    "::mlir::UnitAttr">;
def EvalActivationEntry : ScheduleField<"EvalActivationEntry", "schedule.eval.activation_entry",
    "::mlir::IntegerAttr">;
def EvalAllowedCallees : ScheduleField<"EvalAllowedCallees", "schedule.eval.allowed_callees",
    "::mlir::ArrayAttr">;
def EvalBody : ScheduleField<"EvalBody", "schedule.eval.body",
    "::mlir::FlatSymbolRefAttr">;
def EvalBorrowedCaptures : ScheduleField<"EvalBorrowedCaptures", "schedule.eval.borrowed_captures",
    "::mlir::UnitAttr">;
def EvalCallClosureRoot : ScheduleField<"EvalCallClosureRoot", "schedule.eval.call_closure_root",
    "::mlir::UnitAttr">;
def EvalCheckpointOnly : ScheduleField<"EvalCheckpointOnly", "schedule.eval.checkpoint_only",
    "::mlir::UnitAttr">;
def EvalCheckpointRoutes : ScheduleField<"EvalCheckpointRoutes", "schedule.eval.checkpoint_routes",
    "::mlir::ArrayAttr">;
def EvalCheckpointSafe : ScheduleField<"EvalCheckpointSafe", "schedule.eval.checkpoint_safe",
    "::mlir::UnitAttr">;
// The driver can still recompile with the generic scheduler, so a failed eval
// call closure check marks the module instead of reporting an error.
def EvalClosureRetryAllowed : ScheduleField<"EvalClosureRetryAllowed", "schedule.eval.closure_retry_allowed",
    "::mlir::UnitAttr">;
def EvalClosureRejected : ScheduleField<"EvalClosureRejected", "schedule.eval.closure_rejected",
    "::mlir::UnitAttr">;
def EvalCompactNbaMetadata : ScheduleField<"EvalCompactNbaMetadata", "schedule.eval.compact_nba_metadata",
    "::mlir::UnitAttr">;
def EvalConditionallyTwoState : ScheduleField<"EvalConditionallyTwoState", "schedule.eval.conditionally_two_state",
    "::mlir::UnitAttr">;
def EvalContinuation : ScheduleField<"EvalContinuation", "schedule.eval.continuation",
    "::mlir::IntegerAttr">;
// Forwarded values are reconstructed from immutable captures or private scratch
// reset on every path before any read; no actor frame state is required.
def EvalReconstructsContinuation : ScheduleField<"EvalReconstructsContinuation", "schedule.eval.reconstructs_continuation",
    "::mlir::UnitAttr">;
def EvalDataflowCandidate : ScheduleField<"EvalDataflowCandidate", "schedule.eval.dataflow_candidate",
    "::mlir::FlatSymbolRefAttr">;
def EvalDataflowExecutor : ScheduleField<"EvalDataflowExecutor", "schedule.eval.dataflow_executor",
    "::mlir::FlatSymbolRefAttr">;
def EvalDataflowFallback : ScheduleField<"EvalDataflowFallback", "schedule.eval.dataflow_fallback",
    "::mlir::FlatSymbolRefAttr">;
def EvalDirectCall : ScheduleField<"EvalDirectCall", "schedule.eval.direct_call",
    "::mlir::UnitAttr">;
def EvalDirectFragment : ScheduleField<"EvalDirectFragment", "schedule.eval.direct_fragment",
    "::mlir::IntegerAttr">;
def EvalDirectOutput : ScheduleField<"EvalDirectOutput", "schedule.eval.direct_output",
    "::mlir::UnitAttr">;
def EvalDiscardableStore : ScheduleField<"EvalDiscardableStore", "schedule.eval.discardable_store",
    "::mlir::UnitAttr">;
def EvalForceTwoState : ScheduleField<"EvalForceTwoState", "schedule.eval.force_two_state",
    "::mlir::UnitAttr">;
def EvalFourStateSource : ScheduleField<"EvalFourStateSource", "schedule.eval.four_state_source",
    "::mlir::FlatSymbolRefAttr">;
def EvalFusionGroup : ScheduleField<"EvalFusionGroup", "schedule.eval.fusion_group",
    "::mlir::IntegerAttr">;
def EvalGenerated : ScheduleField<"EvalGenerated", "schedule.eval.generated",
    "::mlir::UnitAttr">;
def EvalGroupChildren : ScheduleField<"EvalGroupChildren", "schedule.eval.group_children",
    "::mlir::ArrayAttr">;
def EvalGroupDomainSelected : ScheduleField<"EvalGroupDomainSelected", "schedule.eval.group_domain_selected",
    "::mlir::UnitAttr">;
def EvalGroupIngress : ScheduleField<"EvalGroupIngress", "schedule.eval.group_ingress",
    "::mlir::FlatSymbolRefAttr">;
def EvalGroupMember : ScheduleField<"EvalGroupMember", "schedule.eval.group_member",
    "::mlir::IntegerAttr">;
def EvalGroupOwner : ScheduleField<"EvalGroupOwner", "schedule.eval.group_owner",
    "::mlir::IntegerAttr">;
def EvalGroupParent : ScheduleField<"EvalGroupParent", "schedule.eval.group_parent",
    "::mlir::FlatSymbolRefAttr">;
def EvalGroupProofDependencies : ScheduleField<"EvalGroupProofDependencies", "schedule.eval.group_proof_dependencies",
    "::mlir::ArrayAttr">;
def EvalGroupProofDomain : ScheduleField<"EvalGroupProofDomain", "schedule.eval.group_proof_domain",
    "::talos::schedule::GroupProofDependencyAttr">;
def EvalInductiveTwoState : ScheduleField<"EvalInductiveTwoState", "schedule.eval.inductive_two_state",
    "::mlir::UnitAttr">;
def EvalInductiveTwoStateAccess : ScheduleField<"EvalInductiveTwoStateAccess", "schedule.eval.inductive_two_state_access",
    "::mlir::UnitAttr">;
def EvalInfallible : ScheduleField<"EvalInfallible", "schedule.eval.infallible",
    "::mlir::UnitAttr">;
// A lowering interface, not an ownership certificate. Tuples describe the
// exact packed lanes carried as values: (unknown-plane, byte, bytes, written).
def EvalValueLanes : ScheduleField<"EvalValueLanes", "schedule.eval.value_lanes",
    "::mlir::DenseI64ArrayAttr">;
def EvalInheritedTwoStateCheckpoint : ScheduleField<"EvalInheritedTwoStateCheckpoint", "schedule.eval.inherited_two_state_checkpoint",
    "::mlir::UnitAttr">;
def EvalInstanceCoordinator : ScheduleField<"EvalInstanceCoordinator", "schedule.eval.instance_coordinator",
    "::mlir::UnitAttr">;
def EvalKernelProofDependencies : ScheduleField<"EvalKernelProofDependencies", "schedule.eval.kernel_proof_dependencies",
    "::mlir::ArrayAttr">;
def EvalLocalPromotionRanges : ScheduleField<"EvalLocalPromotionRanges", "schedule.eval.local_promotion_ranges",
    "::mlir::DenseI64ArrayAttr">;
// Activation-local, read-only proof for conditionally unobserved ranges.
// Its result must never be published as a persistent knownness certificate.
def EvalConditionalPromotionProbe : ScheduleField<"EvalConditionalPromotionProbe", "schedule.eval.conditional_promotion_probe",
    "::mlir::FlatSymbolRefAttr">;
def EvalConditionalPromotionRanges : ScheduleField<"EvalConditionalPromotionRanges", "schedule.eval.conditional_promotion_ranges",
    "::mlir::DenseI64ArrayAttr">;
// Exact dependencies of a private scalar knownness cache. Its byte certifies
// these bits only; it has no scheduler owner, pending word, or route selector.
def EvalKnownRangeDependencies : ScheduleField<"EvalKnownRangeDependencies", "schedule.eval.known_range_dependencies",
    "::mlir::DenseI64ArrayAttr">;
def EvalMaterializedGroupCalls : ScheduleField<"EvalMaterializedGroupCalls", "schedule.eval.materialized_group_calls",
    "::mlir::IntegerAttr">;
def EvalMayTerminate : ScheduleField<"EvalMayTerminate", "schedule.eval.may_terminate",
    "::mlir::UnitAttr">;
def EvalNbaProofDependencies : ScheduleField<"EvalNbaProofDependencies", "schedule.eval.nba_proof_dependencies",
    "::mlir::ArrayAttr">;
def EvalOrderedNbaQueue : ScheduleField<"EvalOrderedNbaQueue", "schedule.eval.ordered_nba_queue",
    "::mlir::UnitAttr">;
def EvalOriginNbaSite : ScheduleField<"EvalOriginNbaSite", "schedule.eval.origin_nba_site",
    "::mlir::IntegerAttr">;
def EvalPathGuardedKnownPreserving : ScheduleField<"EvalPathGuardedKnownPreserving", "schedule.eval.path_guarded_known_preserving",
    "::mlir::UnitAttr">;
def EvalPathGuardedTwoState : ScheduleField<"EvalPathGuardedTwoState", "schedule.eval.path_guarded_two_state",
    "::mlir::UnitAttr">;
def EvalPathKnownPredicate : ScheduleField<"EvalPathKnownPredicate", "schedule.eval.path_known_predicate",
    "::mlir::UnitAttr">;
def EvalPathKnownProbe : ScheduleField<"EvalPathKnownProbe", "schedule.eval.path_known_probe",
    "::mlir::FlatSymbolRefAttr">;
def EvalPathProbeRoutes : ScheduleField<"EvalPathProbeRoutes", "schedule.eval.path_probe_routes",
    "::mlir::ArrayAttr">;
// The design contains value change dump tasks (IEEE 1800-2023 21.7): the
// generated periodic loop runs the runtime's end-of-slot dump hook whenever a
// dump file is open.
def EvalPostponedObservers : ScheduleField<"EvalPostponedObservers", "schedule.eval.postponed_observers",
    "::mlir::UnitAttr">;
// A closed group retaining its proved control flow and exact memory accesses.
def EvalControlFlowDataflow : ScheduleField<"EvalControlFlowDataflow", "schedule.eval.control_flow_dataflow",
    "::mlir::UnitAttr">;
// Profitability hint for a group using control flow to avoid eager evaluation.
// Refresh pending proofs before its computation; the same X/Z proof is required.
def EvalRefreshGroupProofs : ScheduleField<"EvalRefreshGroupProofs", "schedule.eval.refresh_group_proofs",
    "::mlir::UnitAttr">;
def EvalPreserveNbaUnknown : ScheduleField<"EvalPreserveNbaUnknown", "schedule.eval.preserve_nba_unknown",
    "::mlir::UnitAttr">;
def EvalPrivateHelper : ScheduleField<"EvalPrivateHelper", "schedule.eval.private_helper",
    "::mlir::UnitAttr">;
def EvalProofCoverage : ScheduleField<"EvalProofCoverage", "schedule.eval.proof_coverage",
    "::mlir::DenseI64ArrayAttr">;
def EvalProofEntries : ScheduleField<"EvalProofEntries", "schedule.eval.proof_entries",
    "::mlir::DenseI64ArrayAttr">;
def EvalUnknownSummaryReported : ScheduleField<"EvalUnknownSummaryReported", "schedule.eval.unknown_summary_reported",
    "::mlir::UnitAttr">;
def EvalProofSlices : ScheduleField<"EvalProofSlices", "schedule.eval.proof_slices",
    "::mlir::DenseI64ArrayAttr">;
def EvalProvenTwoStateCall : ScheduleField<"EvalProvenTwoStateCall", "schedule.eval.proven_two_state_call",
    "::mlir::UnitAttr">;
def EvalRankedMembers : ScheduleField<"EvalRankedMembers", "schedule.eval.ranked_members",
    "::mlir::DenseI32ArrayAttr">;
def EvalUnconditionalMembers : ScheduleField<"EvalUnconditionalMembers", "schedule.eval.unconditional_members",
    "::mlir::DenseI32ArrayAttr">;
def EvalRawCaptures : ScheduleField<"EvalRawCaptures", "schedule.eval.raw_captures",
    "::mlir::UnitAttr">;
def EvalReadyWordCount : ScheduleField<"EvalReadyWordCount", "schedule.eval.ready_word_count",
    "::mlir::IntegerAttr">;
def EvalReconstructsContinuationArgs : ScheduleField<"EvalReconstructsContinuationArgs", "schedule.eval.reconstructs_continuation_args",
    "::mlir::UnitAttr">;
def EvalRouteProofDependencies : ScheduleField<"EvalRouteProofDependencies", "schedule.eval.route_proof_dependencies",
    "::talos::schedule::RouteProofDependencyAttr">;
def EvalRuntimeCalendar : ScheduleField<"EvalRuntimeCalendar", "schedule.eval.runtime_calendar",
    "::mlir::UnitAttr">;
def EvalAssertionObservers : ScheduleField<"EvalAssertionObservers", "schedule.eval.assertion_observers",
    "::mlir::BoolAttr">;
def EvalRuntimeNbaFallback : ScheduleField<"EvalRuntimeNbaFallback", "schedule.eval.runtime_nba_fallback",
    "::mlir::UnitAttr">;
def EvalRuntimeNbaRequired : ScheduleField<"EvalRuntimeNbaRequired", "schedule.eval.runtime_nba_required",
    "::mlir::UnitAttr">;
// The published root's runtime observers are all runtime-routed static fanout
// waits. Periodic handoff declines while one is live; a shared calendar drains
// them in every slot.
def EvalRuntimeRoutedPublication : ScheduleField<"EvalRuntimeRoutedPublication", "schedule.eval.runtime_routed_publication",
    "::mlir::UnitAttr">;
// A store that performs an NBA update early: a clocked kernel's direct store
// (IEEE 1800-2023 4.5, 10.4.2). The evaluations its transition causes may run
// after the remaining updates of its NBA region (4.5, 4.6(b), 4.7), so
// generated fanout publishes their wakes into the held ready set, which the
// coordinator merges once those updates are complete.
def EvalNbaEquivalentStore : ScheduleField<"EvalNbaEquivalentStore", "schedule.eval.nba_equivalent_store",
    "::mlir::UnitAttr">;
// On the held ready set's global: the sorted leaf words a held publication can
// reach. The coordinator merges only these.
def EvalNbaHeldWords : ScheduleField<"EvalNbaHeldWords", "schedule.eval.nba_held_words",
    "::mlir::DenseI32ArrayAttr">;
def EvalSegmentHelpers : ScheduleField<"EvalSegmentHelpers", "schedule.eval.segment_helpers",
    "::mlir::ArrayAttr">;
def EvalSelectedTwoState : ScheduleField<"EvalSelectedTwoState", "schedule.eval.selected_two_state",
    "::mlir::UnitAttr">;
def EvalSourceOwner : ScheduleField<"EvalSourceOwner", "schedule.eval.source_owner",
    "::talos::schedule::SourceOwnerAttr">;
def EvalSourceOwners : ScheduleField<"EvalSourceOwners", "schedule.eval.source_owners",
    "::mlir::ArrayAttr">;
def EvalSsaReadyWords : ScheduleField<"EvalSsaReadyWords", "schedule.eval.ssa_ready_words",
    "::mlir::IntegerAttr">;
def EvalSsaUnknownRanges : ScheduleField<"EvalSsaUnknownRanges", "schedule.eval.ssa_unknown_ranges",
    "::mlir::IntegerAttr">;
def EvalSsaValueRanges : ScheduleField<"EvalSsaValueRanges", "schedule.eval.ssa_value_ranges",
    "::mlir::IntegerAttr">;
// A generated proof-publication helper consumes explicit deltas and changes
// only proof metadata. It cannot read state, run observers or reenter actors.
def EvalStateMetadataOnly : ScheduleField<"EvalStateMetadataOnly", "schedule.eval.state_metadata_only",
    "::mlir::UnitAttr">;
def EvalTier2Convergence : ScheduleField<"EvalTier2Convergence", "schedule.eval.tier2_convergence",
    "::mlir::UnitAttr">;
def EvalTrustedTwoStateClosure : ScheduleField<"EvalTrustedTwoStateClosure", "schedule.eval.trusted_two_state_closure",
    "::mlir::UnitAttr">;
def EvalTwoStateVariant : ScheduleField<"EvalTwoStateVariant", "schedule.eval.two_state_variant",
    "::mlir::FlatSymbolRefAttr">;
def EvalTwoStateZeroUnknown : ScheduleField<"EvalTwoStateZeroUnknown", "schedule.eval.two_state_zero_unknown",
    "::mlir::UnitAttr">;
def EvalUnknownWriteRange : ScheduleField<"EvalUnknownWriteRange", "schedule.eval.unknown_write_range",
    "::mlir::DenseI64ArrayAttr">;
// Conservative physical byte interval [begin, end) of a bounds-checked
// canonical access. It includes padding and neighboring bytes of its window.
def EvalStateAccessBytes : ScheduleField<"EvalStateAccessBytes", "schedule.eval.state_access_bytes",
    "::mlir::DenseI64ArrayAttr">;
// Immutable source ownership projected into lowering. Entries contain logical
// descriptor/root identity, exact canonical range, captured mask and region.
def EvalTransactionRoots : ScheduleField<"EvalTransactionRoots", "schedule.eval.transaction_roots",
    "::mlir::ArrayAttr">;
// Semantic roles emitted at NBA lowering, rather than recovered from GEPs.
def EvalPendingDirtyRoot : ScheduleField<"EvalPendingDirtyRoot", "schedule.eval.pending_dirty_root",
    "::mlir::IntegerAttr">;
def EvalPendingSummaryRoot : ScheduleField<"EvalPendingSummaryRoot", "schedule.eval.pending_summary_root",
    "::mlir::IntegerAttr">;
// Literal target captured by native lowering: root, state, width, mask,
// region, semantic site. Every source site must have the same certified form.
def EvalPendingStageSpec : ScheduleField<"EvalPendingStageSpec", "schedule.eval.pending_stage_spec",
    "::mlir::DenseI64ArrayAttr">;
def EvalPendingRuntimeRoot : ScheduleField<"EvalPendingRuntimeRoot", "schedule.eval.pending_runtime_root",
    "::mlir::IntegerAttr">;
def EvalPendingMaskAtCommit : ScheduleField<"EvalPendingMaskAtCommit", "schedule.eval.pending_mask_at_commit",
    "::mlir::UnitAttr">;
def EvalUnsupportedCheckpointOwner : ScheduleField<"EvalUnsupportedCheckpointOwner", "schedule.eval.unsupported_checkpoint_owner",
    "::mlir::StringAttr">;
def NativeAssumeCleanSpecialization : ScheduleField<"NativeAssumeCleanSpecialization", "schedule.native.assume_clean_specialization",
    "::mlir::UnitAttr">;
def NativeCleanEvalBody : ScheduleField<"NativeCleanEvalBody", "schedule.native.clean_eval_body",
    "::mlir::UnitAttr">;
def NativeScheduler : ScheduleField<"NativeScheduler", "schedule.native_scheduler",
    "::talos::schedule::NativeSchedulerModeAttr">;
def NativeSchedulerAutoRequested : ScheduleField<"NativeSchedulerAutoRequested", "schedule.native_scheduler.auto_requested",
    "::mlir::UnitAttr">;
def NbaChangeWatched : ScheduleField<"NbaChangeWatched", "schedule.nba.change_watched",
    "::mlir::DenseI64ArrayAttr">;
def NbaPrivateInfluence : ScheduleField<"NbaPrivateInfluence", "schedule.nba.private_influence",
    "::mlir::DenseI64ArrayAttr">;
// Source-only observer proof, usable by a closed writable-VPI executor with
// observation/override guards and canonical publication at foreign cuts.
// Never an unconditional permission for source folding or dead-state removal.
def NbaGuardedPrivateInfluence : ScheduleField<"NbaGuardedPrivateInfluence", "schedule.nba.guarded_private_influence",
    "::mlir::DenseI64ArrayAttr">;
// Complete source-process inventory before fusion adds private scratch.
// Absence means unknown; an empty array certifies no intervening writers.
def NbaImmediateWriters : ScheduleField<"NbaImmediateWriters", "schedule.nba.immediate_writers",
    "::mlir::DenseI64ArrayAttr">;
def NbaTransientObservable : ScheduleField<"NbaTransientObservable", "schedule.nba.transient_observable",
    "::mlir::DenseI64ArrayAttr">;
def BoundedLoopHeader : ScheduleField<"BoundedLoopHeader", "schedule.bounded_loop_header",
    "::mlir::UnitAttr">;
def BoundedLoopLatch : ScheduleField<"BoundedLoopLatch", "schedule.bounded_loop_latch",
    "::mlir::UnitAttr">;
def ClockedControl : ScheduleField<"ClockedControl", "schedule.clocked_control",
    "::mlir::UnitAttr">;
def ClockedSamplePlan : ScheduleField<"ClockedSamplePlan", "schedule.clocked_sample_plan",
    "::talos::schedule::ClockedSamplePlanAttr">;
def ComputeKernels : ScheduleField<"ComputeKernels", "schedule.compute_kernels",
    "::mlir::ArrayAttr">;
def PeriodicControl : ScheduleField<"PeriodicControl", "schedule.periodic_control",
    "::mlir::UnitAttr">;
def ProceduralEventWait : ScheduleField<"ProceduralEventWait", "schedule.procedural_event_wait",
    "::mlir::UnitAttr">;
def RepeatingAlwaysWait : ScheduleField<"RepeatingAlwaysWait", "schedule.repeating_always_wait",
    "::mlir::UnitAttr">;
def StaticBodyFusion : ScheduleField<"StaticBodyFusion", "schedule.static_body_fusion",
    "::mlir::ArrayAttr">;
def StaticFusion : ScheduleField<"StaticFusion", "schedule.static_fusion",
    "::mlir::ArrayAttr">;
def StaticSpecialization : ScheduleField<"StaticSpecialization", "schedule.static_specialization",
    "::talos::schedule::StaticSpecializationAttr">;
def StaticSuperstep : ScheduleField<"StaticSuperstep", "schedule.static_superstep",
    "::talos::schedule::StaticSuperstepAttr">;
def ThreeTierSchedule : ScheduleField<"ThreeTierSchedule", "schedule.three_tier_schedule",
    "::talos::schedule::ThreeTierScheduleAttr">;
def TopLevelWildcardWait : ScheduleField<"TopLevelWildcardWait", "schedule.top_level_wildcard_wait",
    "::mlir::UnitAttr">;
def NativeRegionBody : ScheduleField<"NativeRegionBody", "schedule.native.region_body", "::mlir::UnitAttr">;
def NativeGuardedSpecializationBody : ScheduleField<"NativeGuardedSpecializationBody", "schedule.native.guarded_specialization_body", "::mlir::UnitAttr">;
// A read whose location was proved known on the executing path: lowering
// loads only its value plane.
def NativeKnownRead : ScheduleField<"NativeKnownRead", "schedule.native.known_read", "::mlir::UnitAttr">;
// A store of a known value whose destination unknown bits are zero: it writes
// only the value plane.
def NativeKnownStore : ScheduleField<"NativeKnownStore", "schedule.native.known_store", "::mlir::UnitAttr">;
// The index of a schedule.known.roots gate's rescan backoff state.
def NativeKnownGate : ScheduleField<"NativeKnownGate", "schedule.native.known_gate", "::mlir::IntegerAttr">;
// The (word, mask) pairs of the unknown summary a schedule.known.roots gate
// tests, by ascending word; empty when every root is two-state, so the test
// holds. Absent when some reference has no summary bit: the test never holds.
def NativeKnownSummaryWords : ScheduleField<"NativeKnownSummaryWords", "schedule.native.known_summary_words", "::mlir::DenseI64ArrayAttr">;
// A function containing two-state copies of known-state versioned regions.
def NativeKnownVersioned : ScheduleField<"NativeKnownVersioned", "schedule.native.known_versioned", "::mlir::UnitAttr">;
// An activation whose entry selects a copy with value-only gated reads.
def NativeKnownActivation : ScheduleField<"NativeKnownActivation", "schedule.native.known_activation", "::mlir::UnitAttr">;
def ObserverCaptureBridge : ScheduleField<"ObserverCaptureBridge", "schedule.observer_capture_bridge", "::mlir::UnitAttr">;
def ConcurrentEosCoordinator : ScheduleField<"ConcurrentEosCoordinator", "schedule.concurrent_eos_coordinator", "::mlir::UnitAttr">;
def PrimitiveName : ScheduleField<"PrimitiveName", "schedule.primitive_name", "::mlir::StringAttr">;
def CovergroupClockingSampler : ScheduleField<"CovergroupClockingSampler", "schedule.covergroup_clocking_sampler", "::mlir::UnitAttr">;
def DeferNetResolution : ScheduleField<"DeferNetResolution", "schedule.defer_net_resolution", "::mlir::UnitAttr">;
def OutlinedPrimitiveMember : ScheduleField<"OutlinedPrimitiveMember", "schedule.outlined_primitive_member", "::mlir::UnitAttr">;
def OutlinedPrimitiveFingerprint : ScheduleField<"OutlinedPrimitiveFingerprint", "schedule.outlined_primitive_fingerprint", "::mlir::StringAttr">;
def ExactDriverId : ScheduleField<"ExactDriverId", "schedule.exact_driver_id", "::mlir::IntegerAttr">;
def ExactDriverLow : ScheduleField<"ExactDriverLow", "schedule.exact_driver_low", "::mlir::IntegerAttr">;
def ComputedEventStartup : ScheduleField<"ComputedEventStartup", "schedule.computed_event_startup", "::mlir::UnitAttr">;
def MaxInlineOps : ScheduleField<"MaxInlineOps", "schedule.native.max_inline_ops", "::mlir::IntegerAttr">;
// Charge every emitted CFG slice independently of ordinary call inlining.
def MaxStatementOps : ScheduleField<"MaxStatementOps", "schedule.native.max_statement_ops", "::mlir::IntegerAttr">;
def EvalTwoStateWrapper : ScheduleField<"EvalTwoStateWrapper", "schedule.eval.two_state_wrapper", "::mlir::UnitAttr">;
def StartsWithoutWaiting : ScheduleField<"StartsWithoutWaiting", "schedule.starts_without_waiting", "::mlir::UnitAttr">;
// An eval owner the runtime creates already waiting at this one continuation
// (IEEE 1800-2023 9.2: no implied order between initial and always
// procedures); its process body never takes a first activation at time zero.
// Set by schedule-admit-native-started-owners, read by makeProcessSpawnHelper.
def NativeStartedAt : ScheduleField<"NativeStartedAt", "schedule.native.started_at", "::mlir::IntegerAttr">;
// A started owner whose first activation is its continuation's activation
// (always_comb/always_latch/continuous shape). It is activated once at time
// zero, after all procedures have started (9.2.2.2, 9.2.2.3, 4.9.1).
def NativeTimeZeroActivation : ScheduleField<"NativeTimeZeroActivation", "schedule.native.time_zero_activation", "::mlir::UnitAttr">;
def PrimeOnSpawn : ScheduleField<"PrimeOnSpawn", "schedule.prime_on_spawn", "::mlir::UnitAttr">;
def DetachedControls : ScheduleField<"DetachedControls", "schedule.detached_controls", "::mlir::UnitAttr">;
def PrioritySignalResume : ScheduleField<"PrioritySignalResume", "schedule.priority_signal_resume", "::mlir::UnitAttr">;
def ProgramOwnerId : ScheduleField<"ProgramOwnerId", "schedule.program_owner_id", "::mlir::IntegerAttr">;
def ConcurrentCancel : ScheduleField<"ConcurrentCancel", "schedule.concurrent_cancel", "::mlir::UnitAttr">;
// IEEE 1800-2023 9.4.2: an `always @(list)` block reshaped body-first with an
// armed bit (talos-sim-arm-event-combinational).
def ArmedCombinational : ScheduleField<"ArmedCombinational", "schedule.armed_combinational", "::mlir::UnitAttr">;
def ConcurrentAbort : ScheduleField<"ConcurrentAbort", "schedule.concurrent_abort", "::mlir::UnitAttr">;
def ConcurrentCancelLevelTrue : ScheduleField<"ConcurrentCancelLevelTrue", "schedule.concurrent_cancel_level_true", "::mlir::UnitAttr">;
def ConcurrentAbortLevelTrue : ScheduleField<"ConcurrentAbortLevelTrue", "schedule.concurrent_abort_level_true", "::mlir::UnitAttr">;
def EventPrimary : ScheduleField<"EventPrimary", "schedule.event_primary", "::mlir::UnitAttr">;
def ObserverWidth : ScheduleField<"ObserverWidth", "schedule.observer_width", "::mlir::IntegerAttr">;
def ObserverFourState : ScheduleField<"ObserverFourState", "schedule.observer_four_state", "::mlir::BoolAttr">;
def OverrideEvaluator : ScheduleField<"OverrideEvaluator", "schedule.override_evaluator", "::mlir::UnitAttr">;
def ConcurrentEosCounted : ScheduleField<"ConcurrentEosCounted", "schedule.concurrent_eos_counted", "::mlir::UnitAttr">;
def ConcurrentReport : ScheduleField<"ConcurrentReport", "schedule.concurrent_report", "::mlir::UnitAttr">;
def ConcurrentCancelObserver : ScheduleField<"ConcurrentCancelObserver", "schedule.concurrent_cancel_observer", "::mlir::UnitAttr">;
def ConcurrentAbortObserver : ScheduleField<"ConcurrentAbortObserver", "schedule.concurrent_abort_observer", "::mlir::UnitAttr">;
def ConcurrentCancelObserverRequest : ScheduleField<"ConcurrentCancelObserverRequest", "schedule.concurrent_cancel_observer_request", "::mlir::ArrayAttr">;
def ConcurrentAbortObserverRequest : ScheduleField<"ConcurrentAbortObserverRequest", "schedule.concurrent_abort_observer_request", "::mlir::ArrayAttr">;

// Physical scheduling metadata retained across native representation conversion.
def NativeConditionOperandBegin : ScheduleField<"NativeConditionOperandBegin", "schedule.native.condition_operand_begin", "::mlir::IntegerAttr">;
def NativeContinuation : ScheduleField<"NativeContinuation", "schedule.native.continuation", "::mlir::IntegerAttr">;
def NativeContinuationOperandBegin : ScheduleField<"NativeContinuationOperandBegin", "schedule.native.continuation_operand_begin", "::mlir::IntegerAttr">;
def NativeDependencyCaptureIndices : ScheduleField<"NativeDependencyCaptureIndices", "schedule.native.dependency_capture_indices", "::mlir::DenseI32ArrayAttr">;
def NativeDependencyKinds : ScheduleField<"NativeDependencyKinds", "schedule.native.dependency_kinds", "::mlir::DenseI32ArrayAttr">;
def NativeDependencyWidths : ScheduleField<"NativeDependencyWidths", "schedule.native.dependency_widths", "::mlir::DenseI32ArrayAttr">;
def NativeInitialPlaneCounts : ScheduleField<"NativeInitialPlaneCounts", "schedule.native.initial_plane_counts", "::mlir::DenseI32ArrayAttr">;
def NativeObserverFourState : ScheduleField<"NativeObserverFourState", "schedule.native.observer_four_state", "::mlir::BoolAttr">;
def NativeObserverId : ScheduleField<"NativeObserverId", "schedule.native.observer_id", "::mlir::IntegerAttr">;
def NativeObserverWidth : ScheduleField<"NativeObserverWidth", "schedule.native.observer_width", "::mlir::IntegerAttr">;
def NativeWaitOffset : ScheduleField<"NativeWaitOffset", "schedule.native.wait_offset", "::mlir::IntegerAttr">;
def NativeWaitSize : ScheduleField<"NativeWaitSize", "schedule.native.wait_size", "::mlir::IntegerAttr">;
def NativeWaitWidths : ScheduleField<"NativeWaitWidths", "schedule.native.wait_widths", "::mlir::DenseI32ArrayAttr">;
