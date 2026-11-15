// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-simplify-bodies{vpi=off}))' | FileCheck %s

// A report queued by a callee belongs to the caller process's innermost
// activation. No disable is required to make this control token observable:
// entering/leaving the activation participates in deferred report flushing.
module {
  simulation.design @callee_reports {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "actor"
    simulation.code_unit.decl 2 in 0 function hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %actor = simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @actor(
    // CHECK: %[[CONTROL:[0-9]+]] = simulation.control.enter 10
    // CHECK: simulation.call @report
    // CHECK: simulation.control.leave %[[CONTROL]]
    simulation.func @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %scope = simulation.control.enter 10
      simulation.call @report(%ctx) : (!simulation.context) -> ()
      simulation.control.leave %scope
      simulation.suspend.change %input to ^body : !simulation.ref<i1>
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %ticket = simulation.assert.deferred_enqueue 1
      simulation.return
    }
  }
}
