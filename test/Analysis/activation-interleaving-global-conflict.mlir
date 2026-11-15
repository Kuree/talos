// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=false},talos-sim-build-compute-graph))' -o %t.before
// RUN: talos-opt %t.before --pass-pipeline='builtin.module(simulation.design(talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true},simulation.func(talos-sim-thread-suspension{active-preemptions-only=true}),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.after
// RUN: FileCheck %s < %t.after
// RUN: talos-opt %t.after --test-talos-simulation-schedule-analysis=preemptions=true -o /dev/null

// Two pulse SCCs (a0,b0 and a1,b1) each choose A,B,A, and producers p0,p1
// read B1 and B0. A whole-body virtual re-arm exposes no partial
// publication and needs no prefix-input order, so those producers impose no
// phase constraint: both cohorts are realized and the ranks stay acyclic
// (IEEE 1800-2023 4.6, 4.7, 9.4.2).
// CHECK-LABEL: simulation.func @a0(
// CHECK: simulation.suspend.delay
// CHECK-SAME: schedule.active_preemption_after = [@b0], schedule.active_preemption_rearm
// CHECK-LABEL: simulation.func @a1(
// CHECK: simulation.suspend.delay
// CHECK-SAME: schedule.active_preemption_after = [@b1], schedule.active_preemption_rearm
// CHECK-LABEL: simulation.func @b0(
// CHECK-NOT: simulation.suspend.delay
// CHECK: simulation.suspend.change
// CHECK-LABEL: simulation.func @b1(
// CHECK-NOT: simulation.suspend.delay
// CHECK: simulation.suspend.change
// CHECK-LABEL: simulation.func @p0(
// CHECK-NOT: simulation.suspend.delay
// CHECK: simulation.suspend.change
// CHECK-LABEL: simulation.func @p1(
// CHECK-NOT: simulation.suspend.delay
// CHECK: simulation.suspend.change

!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @phase_conflict {
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
  simulation.storage.decl 9 in 0 : !b design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "a#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.code_unit.decl 3 in 0 always_comb hierarchy "b#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.code_unit.decl 5 in 0 always_comb hierarchy "p#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @"a#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
    simulation.spawn @"b#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
    simulation.spawn @"p#"(%ctx) {test.replicate = 2 : i64} : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @"a#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
    %out = simulation.context.storage %ctx[0] {test.replicate_stride = {id = 2 : i64}} : !r
    %saved = simulation.context.storage %ctx[4] {test.replicate_stride = {id = 2 : i64}} : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    %r1 = simulation.context.storage %ctx[1] {test.replicate_stride = {id = 2 : i64}} : !r
    %r8 = simulation.context.storage %ctx[8] {test.replicate_stride = {id = 1 : i64}} : !r
    cf.br ^body
  ^body:
    %v1 = simulation.ref.load %r1 : !r -> !b
    simulation.ref.store %v1 to %saved : !b, !r
    %v8 = simulation.ref.load %r8 : !r -> !b
    simulation.ref.store %v8 to %saved : !b, !r
    simulation.ref.store %zero to %out : !b, !r
    simulation.ref.store %one to %out : !b, !r
    simulation.suspend.any %r1, %r8 edges [0, 0] to ^body : !r, !r
  }
  simulation.func @"b#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
    %out = simulation.context.storage %ctx[1] {test.replicate_stride = {id = 2 : i64}} : !r
    %saved = simulation.context.storage %ctx[5] {test.replicate_stride = {id = 2 : i64}} : !r
    %r0 = simulation.context.storage %ctx[0] {test.replicate_stride = {id = 2 : i64}} : !r
    %zero = simulation.logic.constant false, false : !b
    %one = simulation.logic.constant true, false : !b
    cf.br ^body
  ^body:
    %v0 = simulation.ref.load %r0 : !r -> !b
    simulation.ref.store %v0 to %saved : !b, !r
    simulation.ref.store %zero to %out : !b, !r
    simulation.ref.store %one to %out : !b, !r
    simulation.suspend.change %r0 to ^body : !r
  }
  simulation.func @"p#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
    %out = simulation.context.storage %ctx[8] {test.replicate_stride = {id = 1 : i64}} : !r
    %in = simulation.context.storage %ctx[3] {test.replicate_stride = {id = -2 : i64}} : !r
    cf.br ^body
  ^body:
    %v = simulation.ref.load %in : !r -> !b
    simulation.ref.store %v to %out : !b, !r
    simulation.suspend.change %in to ^body : !r
  }
}
