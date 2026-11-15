// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-specialize-static-state-nba))' | FileCheck %s --check-prefix=UNKNOWN
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension{specialize-handle-tails=true}),talos-sim-build-compute-graph,talos-sim-specialize-static-state-nba,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=STATIC

// A shared tail hides a finite choice of two concrete NBA destinations.
// Before specialization, its unknown commit must prevent every root from
// bypassing the ordered runtime queue. Edge specialization exposes both
// roots without changing either dynamic path's RHS captures or NBA order
// (IEEE 1800-2023 4.6(b), 10.4.2).
// UNKNOWN: #schedule.static_state_root<descriptor = 1, width = 8, direct = true, guarded = false, nba = false>
// UNKNOWN: #schedule.static_state_root<descriptor = 2, width = 8, direct = true, guarded = false, nba = false>
// STATIC: #schedule.static_state_root<descriptor = 1, width = 8, direct = true, guarded = false, nba = true>
// STATIC: #schedule.static_state_root<descriptor = 2, width = 8, direct = true, guarded = false, nba = true>
// STATIC-LABEL: simulation.func @writer(
// STATIC-SAME: %[[A:arg[0-9]+]]: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}
// STATIC-SAME: %[[B:arg[0-9]+]]: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}
// STATIC-SAME: %[[ONE:arg[0-9]+]]: !simulation.logic<8> {simulation.capture_kind = 2 : i32}
// STATIC-SAME: %[[TWO:arg[0-9]+]]: !simulation.logic<8> {simulation.capture_kind = 2 : i32}
// STATIC: simulation.nba.enqueue %[[ONE]] to %[[B]]
// STATIC-NEXT: simulation.nba.enqueue %[[TWO]] to %[[A]]
// STATIC: simulation.nba.enqueue %[[ONE]] to %[[A]]
// STATIC-NEXT: simulation.nba.enqueue %[[TWO]] to %[[A]]

!byte = !simulation.logic<8>
!ref = !simulation.ref<!byte>
module {
  simulation.design @finite_alias {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !byte design
    simulation.storage.decl 2 in 0 : !byte design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_ff hierarchy "top.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %clock = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %a = simulation.context.storage %ctx[1] : !ref
      %b = simulation.context.storage %ctx[2] : !ref
      %select = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      %two = simulation.logic.constant 2 : i8, 0 : i8 : !byte
      %p = simulation.spawn @writer(%ctx, %clock, %select, %a, %b, %one, %two) : !simulation.context, !simulation.ref<i1>, !simulation.ref<i1>, !ref, !ref, !byte, !byte -> !simulation.process
      simulation.return
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clock: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %select: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %a: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %b: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %one: !byte {simulation.capture_kind = 2 : i32}, %two: !byte {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 5 : i32, code_unit_id = 1 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !simulation.ref<i1>
    ^body:
      %choice = simulation.ref.load %select : !simulation.ref<i1> -> i1
      cf.cond_br %choice, ^write(%a : !ref), ^write(%b : !ref)
    ^write(%target: !ref):
      simulation.nba.enqueue %one to %target : (!byte, !ref) -> ()
      simulation.nba.enqueue %two to %a : (!byte, !ref) -> ()
      cf.br ^wait
    }
  }
}
