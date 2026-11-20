// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion))' | FileCheck %s

// IEEE 1800-2023 9.4.2.3, 4.6(b): an iff guard is evaluated with the update
// that triggers its event, so its reads constrain NBA publication order. The
// resumed body is an ordinary event whose order against the remaining
// updates is unspecified (4.7), so a private value read there, unlike a
// private guard (simulation-nba-private-conditional-read.mlir), does not
// withhold the design-wide certificate.
// CHECK-LABEL: simulation.design @private_body
// CHECK-SAME: schedule.nba.transient_observable = array<i64: 0, 1>

!ref = !simulation.ref<i1>
module {
  simulation.design @private_body {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "conditional"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %guard = simulation.context.storage %ctx[1] : !ref
      %zero = arith.constant false
      %private = simulation.ref.alloc %zero : i1 -> !ref
      %p = simulation.spawn @conditional(%ctx, %clk, %guard, %private) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func private @conditional(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %guard: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %count: !ref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge_iff posedge %clk iff %guard to ^body : !ref, !ref
    ^body:
      %old = simulation.ref.load %count : !ref -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %count : i1, !ref
      cf.br ^wait
    }
  }
}
