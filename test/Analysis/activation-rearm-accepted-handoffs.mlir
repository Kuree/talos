// RUN: talos-opt %s -split-input-file '--test-talos-activation-regions=functions=first,second,a,b,c,d verify-prepared-views=true canonical-controls=true reaching-values=true publications=true rearm-interleaving=true interleaving=true order=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -split-input-file -o %t.original
// RUN: diff %t.original %t.analyzed
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-simulation-schedule-analysis{preemptions=true})' -o %t.lowered 2>&1 | FileCheck %s --check-prefix=RANK
// RUN: FileCheck %s --check-prefix=LOWER < %t.lowered
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph),encode-talos-sim-to-bytecode{vpi=off},test-talos-print-bytecode)' -o /dev/null 2>&1 | FileCheck %s --check-prefix=BYTECODE

// Re-arm plans for two-process pulse cycles whose witness holds. Each plan
// breaks the cycle with an active preemption on the chosen owners; the
// original publications, saved reads, waits and observers remain.

// Named-block bookkeeping with no disable or deferred report is unobservable;
// the live control token survives across the partial Active handoff.
// CHECK: regions @first valid=1
// CHECK: regions @second valid=1
// CHECK: rearm interleaving: components=1
// CHECK-NEXT: rearm plan: handoffs=2 preemptions= @first
// LOWER-LABEL: design @named_blocks
// LOWER-LABEL: simulation.func @first(
// LOWER: %[[SCOPE:[0-9]+]] = simulation.control.enter 10
// LOWER: simulation.suspend.delay
// LOWER-SAME: %[[SCOPE]]
// LOWER-SAME: resume_region = 2 : i32
// LOWER: simulation.control.leave
// BYTECODE: intrinsic {{[0-9]+}}: id=0x00010206 inputs=0 outputs=1 flags=10
// BYTECODE: intrinsic {{[0-9]+}}: id=0x00010207 inputs=1 outputs=0 flags=0
!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-i64:64"} {
  simulation.design @named_blocks {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "second"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %out = simulation.context.storage %ctx[0] : !ref
      %in = simulation.context.storage %ctx[1] : !ref
      %saved = simulation.context.storage %ctx[2] : !ref
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      %scope = simulation.control.enter 10
      simulation.ref.store %zero to %out : i1, !ref
      simulation.ref.store %one to %out : i1, !ref
      %value = simulation.ref.load %in : !ref -> i1
      simulation.ref.store %value to %saved : i1, !ref
      simulation.control.leave %scope
      simulation.suspend.change %in to ^body : !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %out = simulation.context.storage %ctx[1] : !ref
      %in = simulation.context.storage %ctx[0] : !ref
      %saved = simulation.context.storage %ctx[3] : !ref
      %zero = arith.constant false
      %one = arith.constant true
      cf.br ^body
    ^body:
      %scope = simulation.control.enter 11
      simulation.ref.store %zero to %out : i1, !ref
      simulation.ref.store %one to %out : i1, !ref
      %value = simulation.ref.load %in : !ref -> i1
      simulation.ref.store %value to %saved : i1, !ref
      simulation.control.leave %scope
      simulation.suspend.change %in to ^body : !ref
    }
  }
}

// -----
// Both bodies read the other's publication BEFORE their own pulses: values
// are acyclic but source order is not. IEEE 1800-2023 4.6/4.7 allow two
// handoffs. All four publications and waits remain; an outside edge observer
// stops pulse erasure. Only @first gets the re-arm.
// CHECK: rearm plan: handoffs=2 preemptions= @first
// CHECK: interleaving order: cyclic refined=2 livelock-witness=1
// CHECK: publication graph: acyclic
// CHECK: region order: cyclic
// LOWER-LABEL: design @earlier_snapshots
// LOWER: simulation.ref.store
// LOWER: simulation.ref.store
// LOWER: simulation.suspend.delay
// LOWER-SAME: resume_region = 2 : i32
// LOWER-NEXT: ^bb
// LOWER: simulation.logic.compare case_ne
// LOWER: cf.cond_br %{{.*}}, ^[[BODY:bb[0-9]+]](%{{.*}}), ^[[WAIT:bb[0-9]+]](
// LOWER-NEXT: ^[[WAIT]](
// LOWER-NEXT: simulation.suspend.change %{{.*}} to ^[[BODY]](
// LOWER-LABEL: simulation.func @second(
// LOWER-NOT: simulation.suspend.delay
// LOWER: simulation.suspend.change
// LOWER-NOT: simulation.suspend.delay
// LOWER-LABEL: simulation.func @observe(
// LOWER: simulation.suspend.edge posedge
// LOWER: simulation.nba.enqueue
// LOWER-NOT: simulation.suspend.delay
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-i64:64"} {
  simulation.design @earlier_snapshots {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "top.first"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "top.second"
    simulation.code_unit.decl 3 in 0 always hierarchy "top.observe"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @first(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @second(%ctx) : !simulation.context -> !simulation.process
      %observer = simulation.spawn @observe(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %saved = simulation.context.storage %ctx[2] : !ref
      cf.br ^body
    ^body:
      %old = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      simulation.ref.store %zero to %y : !bit, !ref
      simulation.ref.store %one to %y : !bit, !ref
      simulation.suspend.change %x to ^body : !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %saved = simulation.context.storage %ctx[3] : !ref
      cf.br ^body
    ^body:
      %old = simulation.ref.load %y : !ref -> !bit
      simulation.ref.store %old to %saved : !bit, !ref
      %zero = simulation.logic.constant false, false : !bit
      %one = simulation.logic.constant true, false : !bit
      simulation.ref.store %zero to %x : !bit, !ref
      simulation.ref.store %one to %x : !bit, !ref
      simulation.suspend.change %y to ^body : !ref
    }
    simulation.func @observe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %x = simulation.context.storage %ctx[0] : !ref
      %y = simulation.context.storage %ctx[1] : !ref
      %saved = simulation.context.storage %ctx[4] : !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %y to ^body : !ref
    ^body:
      %value = simulation.ref.load %x : !ref -> !bit
      simulation.nba.enqueue %value to %saved : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----
// Two feedback cycles joined into one SCC: the whole-body optimum holds two
// actors (@a, @c) before re-arm, resumed phases separate from their prefixes.
// CHECK: rearm plan: handoffs=5 preemptions= @a @c
// CHECK: livelock-witness=1
// LOWER-LABEL: design @two_cycles
// LOWER-LABEL: simulation.func @a(
// LOWER: simulation.suspend.delay
// LOWER-SAME: schedule.active_preemption_resume =
// LOWER-SAME: schedule.active_preemption_runs =
// LOWER: simulation.suspend.any
// LOWER-LABEL: simulation.func @c(
// LOWER: simulation.suspend.delay
// LOWER-SAME: schedule.active_preemption_runs =
// RANK: preemption @a ordered=1
// RANK: preemption @c ordered=1
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-i64:64"} {
 simulation.design @two_cycles {
 simulation.scope.decl 0
 simulation.storage.decl 0 in 0 : !bit design
 simulation.storage.decl 1 in 0 : !bit design
 simulation.storage.decl 2 in 0 : !bit design
 simulation.storage.decl 3 in 0 : !bit design
 simulation.storage.decl 4 in 0 : !bit design
 simulation.storage.decl 5 in 0 : !bit design
 simulation.storage.decl 6 in 0 : !bit design
 simulation.storage.decl 7 in 0 : !bit design
 simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
 simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
 simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
 simulation.code_unit.decl 4 in 0 always_comb hierarchy "d"
 simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
 %pa = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
 %pb = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
 %pc = simulation.spawn @c(%ctx) : !simulation.context -> !simulation.process
 %pd = simulation.spawn @d(%ctx) : !simulation.context -> !simulation.process
 simulation.return
 }
 simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
 %out = simulation.context.storage %ctx[0] : !ref
 %saved = simulation.context.storage %ctx[4] : !ref
 %r1 = simulation.context.storage %ctx[1] : !ref
 %r3 = simulation.context.storage %ctx[3] : !ref
 cf.br ^body
 ^body:
 %v1 = simulation.ref.load %r1 : !ref -> !bit
 %v3 = simulation.ref.load %r3 : !ref -> !bit
 simulation.ref.store %v1 to %saved : !bit, !ref
 simulation.ref.store %v3 to %saved : !bit, !ref
 %zero = simulation.logic.constant false, false : !bit
 %one = simulation.logic.constant true, false : !bit
 simulation.ref.store %zero to %out : !bit, !ref
 simulation.ref.store %one to %out : !bit, !ref
 simulation.suspend.any %r1, %r3 edges [0, 0] to ^body : !ref, !ref
 }
 simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
 %out = simulation.context.storage %ctx[1] : !ref
 %saved = simulation.context.storage %ctx[5] : !ref
 %r0 = simulation.context.storage %ctx[0] : !ref
 cf.br ^body
 ^body:
 %v0 = simulation.ref.load %r0 : !ref -> !bit
 %old = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
 simulation.ref.store %old to %saved : !bit, !ref
 %zero = simulation.logic.constant false, false : !bit
 %one = simulation.logic.constant true, false : !bit
 simulation.ref.store %zero to %out : !bit, !ref
 simulation.ref.store %one to %out : !bit, !ref
 simulation.suspend.change %r0 to ^body : !ref
 }
 simulation.func @c(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
 %out = simulation.context.storage %ctx[2] : !ref
 %saved = simulation.context.storage %ctx[6] : !ref
 %r1 = simulation.context.storage %ctx[1] : !ref
 %r3 = simulation.context.storage %ctx[3] : !ref
 cf.br ^body
 ^body:
 %v1 = simulation.ref.load %r1 : !ref -> !bit
 %v3 = simulation.ref.load %r3 : !ref -> !bit
 simulation.ref.store %v1 to %saved : !bit, !ref
 simulation.ref.store %v3 to %saved : !bit, !ref
 %zero = simulation.logic.constant false, false : !bit
 %one = simulation.logic.constant true, false : !bit
 simulation.ref.store %zero to %out : !bit, !ref
 simulation.ref.store %one to %out : !bit, !ref
 simulation.suspend.any %r1, %r3 edges [0, 0] to ^body : !ref, !ref
 }
 simulation.func @d(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
 %out = simulation.context.storage %ctx[3] : !ref
 %saved = simulation.context.storage %ctx[7] : !ref
 %r2 = simulation.context.storage %ctx[2] : !ref
 cf.br ^body
 ^body:
 %v2 = simulation.ref.load %r2 : !ref -> !bit
 %old = simulation.logic.unary bit_not %v2 : (!bit) -> !bit
 simulation.ref.store %old to %saved : !bit, !ref
 %zero = simulation.logic.constant false, false : !bit
 %one = simulation.logic.constant true, false : !bit
 simulation.ref.store %zero to %out : !bit, !ref
 simulation.ref.store %one to %out : !bit, !ref
 simulation.suspend.change %r2 to ^body : !ref
 }
 }
}
