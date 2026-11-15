// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --implicit-check-not=simulation.suspend.delay

// The eval coordinator never executes an implementation Active preemption.
// A design forced onto it keeps its source schedule rather than becoming a
// compile error. With schedule.native_scheduler = 1 (generic) the same
// cohort is realized as a whole-body re-arm.
// CHECK-LABEL: simulation.design @forced_eval
// CHECK-LABEL: simulation.func @a(
// CHECK: simulation.suspend.change
// CHECK-LABEL: simulation.func @b(
// CHECK: simulation.suspend.change

!b = !simulation.logic<1>
!r = !simulation.ref<!b>
module attributes {schedule.native_scheduler = 3 : i32} {
  simulation.design @forced_eval {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !b design
    simulation.storage.decl 1 in 0 : !b design
    simulation.storage.decl 2 in 0 : !b design
    simulation.storage.decl 3 in 0 : !b design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %out = simulation.context.storage %ctx[0] : !r
      %fromB = simulation.context.storage %ctx[1] : !r
      %saved = simulation.context.storage %ctx[2] : !r
      %zero = simulation.logic.constant false, false : !b
      %one = simulation.logic.constant true, false : !b
      cf.br ^body
    ^body:
      %v = simulation.ref.load %fromB : !r -> !b
      simulation.ref.store %v to %saved : !b, !r
      simulation.ref.store %zero to %out : !b, !r
      simulation.ref.store %one to %out : !b, !r
      simulation.suspend.change %fromB to ^body : !r
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %out = simulation.context.storage %ctx[1] : !r
      %fromA = simulation.context.storage %ctx[0] : !r
      %saved = simulation.context.storage %ctx[3] : !r
      %zero = simulation.logic.constant false, false : !b
      %one = simulation.logic.constant true, false : !b
      cf.br ^body
    ^body:
      %v = simulation.ref.load %fromA : !r -> !b
      simulation.ref.store %v to %saved : !b, !r
      simulation.ref.store %zero to %out : !b, !r
      simulation.ref.store %one to %out : !b, !r
      simulation.suspend.change %fromA to ^body : !r
    }
  }
}
