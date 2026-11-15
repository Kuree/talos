// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,test-talos-activation-regions{verify-prepared-views=true functions=a0,a1,a2,a3,a4,a5,a6,a7,a8 rearm-interleaving=true interleaving=true})' 2>&1 | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=SOURCE

// The exact interleaving proof is bounded to eight owners. Nine owners that
// all pulse and watch one input are rejected: unavailable is conservative,
// so no heuristic handoff may escape and the processes are kept (4.6).
// CHECK: rearm plan: unavailable
// CHECK: livelock-witness=0 preserved=1
// SOURCE-NOT: schedule.active_preemption
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @nine_owners {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design {test.replicate = 9 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "a#" {test.replicate = 9 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @"a#"(%ctx) {test.replicate = 9 : i64} : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @"a#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, test.replicate = 9 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
    %x = simulation.context.storage %ctx[0] : !r
    %saved = simulation.context.storage %ctx[1] {test.replicate_stride = {id = 1 : i64}} : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    %v = simulation.ref.load %x : !r -> !b
    simulation.ref.store %v to %saved : !b, !r
    simulation.ref.store %zero to %x : !b, !r
    simulation.ref.store %one to %x : !b, !r
    simulation.suspend.change %x to ^body : !r
  }
}
