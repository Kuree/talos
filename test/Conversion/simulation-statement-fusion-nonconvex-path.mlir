// RUN: talos-opt %s --mlir-print-op-on-diagnostic=false --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false explain=true}))' -o /dev/null 2>&1 | FileCheck %s

// The A/B publication graph is acyclic, but contracting those owners would
// hide the path A -> outside -> A through a preserved ordinary process.
// Keep the original executors and report the actual path blocking fusion.
// CHECK: statement component rejected: dependency path leaves and reenters fusion
// CHECK-SAME: dependency path: @a @outside @a

!r = !simulation.ref<i8>
module {
  simulation.design @nonconvex {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always hierarchy "outside"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @a(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @outside(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %output = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %answer = simulation.ref.load %response : !r -> i8
      simulation.ref.store %answer to %output : i8, !r
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %address : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %next to %response : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
    simulation.func @outside(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %input = simulation.context.storage %ctx[0] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      simulation.ref.store %value to %input : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
  }
}
