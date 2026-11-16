// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion))' | FileCheck %s

// IEEE 1800-2023 9.4.2.3, 13.5.2: a private guard still carries its value
// into the iff decision. Knowing it aliases no design root does not prove
// absence of influence through its producer. Until that transfer is modeled,
// the conditional observer cannot certify design-wide NBA merge safety.
// CHECK-LABEL: simulation.design @private_condition
// CHECK-NOT: schedule.nba.transient_observable
// CHECK: simulation.scope.decl

!ref = !simulation.ref<i1>
module {
  simulation.design @private_condition {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "conditional"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %zero = arith.constant false
      %private = simulation.ref.alloc %zero : i1 -> !ref
      %p = simulation.spawn @conditional(%ctx, %clk, %private) : !simulation.context, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func private @conditional(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %guard: !ref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      simulation.suspend.edge_iff posedge %clk iff %guard to ^done : !ref, !ref
    ^done:
      simulation.return
    }
  }
}
