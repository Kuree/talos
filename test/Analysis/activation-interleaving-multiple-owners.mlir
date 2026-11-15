// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,test-talos-activation-regions{verify-prepared-views=true functions=x0,x1,y0,y1 rearm-interleaving=true interleaving=true order=true})' -o /dev/null 2>&1 | FileCheck %s --check-prefix=PROOF
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.source
// RUN: FileCheck %s --check-prefix=SOURCE < %t.source
// RUN: talos-opt %t.source --test-talos-simulation-schedule-analysis=preemptions=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=RANK

// Two feedback cycles joined into one SCC: breaking one leaves the other
// live, so the optimum holds two original actors before re-arm, with resumed
// phases separate from prefixes; publications, saved reads, waits and the
// outside observer remain (IEEE 1800-2023 4.6, 9.2.2.2).
// PROOF: rearm plan: handoffs=5 preemptions= @x0 @x1
// PROOF: interleaving order: acyclic{{.*}}handoffs=5
// PROOF: livelock-witness=1
// SOURCE-LABEL: simulation.func @x0(
// SOURCE: simulation.ref.store
// SOURCE: simulation.ref.store
// SOURCE: simulation.suspend.delay
// SOURCE-SAME: resume_region = 2 : i32
// SOURCE-SAME: schedule.active_preemption_resume =
// SOURCE-SAME: schedule.active_preemption_runs =
// SOURCE: simulation.ref.load
// SOURCE: simulation.suspend.any
// SOURCE-LABEL: simulation.func @x1(
// SOURCE: simulation.suspend.delay
// SOURCE-SAME: schedule.active_preemption_resume =
// SOURCE-SAME: schedule.active_preemption_runs =
// SOURCE: simulation.suspend.any
// SOURCE-LABEL: simulation.func @observer(
// SOURCE: simulation.suspend.any
// SOURCE: simulation.nba.enqueue
// RANK: preemption @x0 ordered=1
// RANK: preemption @x1 ordered=1

!b = !simulation.logic<1>
!r = !simulation.ref<!b>
module attributes {native.debug_timing} {
  simulation.design @two_interior_cycles {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !b design
    simulation.storage.decl 1 in 0 : !b design
    simulation.storage.decl 2 in 0 : !b design
    simulation.storage.decl 3 in 0 : !b design
    simulation.storage.decl 4 in 0 : !b design
    simulation.storage.decl 5 in 0 : !b design
    simulation.storage.decl 6 in 0 : !b design
    simulation.storage.decl 7 in 0 : !b design
    simulation.storage.decl 8 in 0 : !b design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "x#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "y#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 5 in 0 always hierarchy "observer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      simulation.spawn @"x#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
      simulation.spawn @"y#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
      simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @"x#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      %out = simulation.context.storage %ctx[0] {test.replicate_stride = {id = 2 : i64}} : !r
      %saved = simulation.context.storage %ctx[4] {test.replicate_stride = {id = 2 : i64}} : !r
      %r1 = simulation.context.storage %ctx[1] : !r
      %r3 = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %zero = simulation.logic.constant false, false : !b
      %one = simulation.logic.constant true, false : !b
      simulation.ref.store %zero to %out : !b, !r
      simulation.ref.store %one to %out : !b, !r
      %v1 = simulation.ref.load %r1 : !r -> !b
      %v3 = simulation.ref.load %r3 : !r -> !b
      simulation.ref.store %v1 to %saved : !b, !r
      simulation.ref.store %v3 to %saved : !b, !r
      simulation.suspend.any %r1, %r3 edges [0, 0] to ^body : !r, !r
    }
    simulation.func @"y#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      %out = simulation.context.storage %ctx[1] {test.replicate_stride = {id = 2 : i64}} : !r
      %saved = simulation.context.storage %ctx[5] {test.replicate_stride = {id = 2 : i64}} : !r
      %in = simulation.context.storage %ctx[0] {test.replicate_stride = {id = 2 : i64}} : !r
      cf.br ^body
    ^body:
      %zero = simulation.logic.constant false, false : !b
      %one = simulation.logic.constant true, false : !b
      simulation.ref.store %zero to %out : !b, !r
      simulation.ref.store %one to %out : !b, !r
      %v = simulation.ref.load %in : !r -> !b
      %old = simulation.logic.unary bit_not %v : (!b) -> !b
      simulation.ref.store %old to %saved : !b, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %r0 = simulation.context.storage %ctx[0] : !r
      %r1 = simulation.context.storage %ctx[1] : !r
      %r2 = simulation.context.storage %ctx[2] : !r
      %r3 = simulation.context.storage %ctx[3] : !r
      %saved = simulation.context.storage %ctx[8] : !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %r0, %r1, %r2, %r3 edges [1, 1, 1, 1] to ^body : !r, !r, !r, !r
    ^body:
      %v = simulation.ref.load %r0 : !r -> !b
      simulation.nba.enqueue %v to %saved : (!b, !r) -> ()
      cf.br ^wait
    }
  }
}
