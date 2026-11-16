// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion))' | FileCheck %s

// IEEE 1800-2023 9.4.2.3: the iff guard is read when clk changes, so its
// actual design root must constrain NBA publication order. References passed
// to outlined processes retain their actual identity (9.3.2, 13.5.2).
// A private writer cannot alias a design root, while private reads retain
// conservative influence admission. A formal change watch also resolves to
// its actual, without becoming an edge/conditional observer.
// CHECK-LABEL: simulation.design @formal_reads
// CHECK-SAME: schedule.nba.change_watched = array<i64: 3>
// CHECK-SAME: schedule.nba.immediate_writers = array<i64>
// CHECK-SAME: schedule.nba.private_influence = array<i64: 2, 3>
// CHECK-SAME: schedule.nba.transient_observable = array<i64: 0, 1>

!bitref = !simulation.ref<i1>
!epochref = !simulation.ref<i64>
module {
  simulation.design @formal_reads {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "conditional"
    simulation.code_unit.decl 3 in 0 always hierarchy "change"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !bitref
      %guard = simulation.context.storage %ctx[1] : !bitref
      %changed = simulation.context.storage %ctx[3] : !bitref
      %zero = arith.constant 0 : i64
      %private = simulation.ref.alloc %zero : i64 -> !epochref
      %p = simulation.spawn @conditional(%ctx, %clk, %guard, %private) : !simulation.context, !bitref, !bitref, !epochref -> !simulation.process
      %c = simulation.spawn @change(%ctx, %changed) : !simulation.context, !bitref -> !simulation.process
      simulation.return
    }
    simulation.func private @conditional(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !bitref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %guard: !bitref {simulation.capture_kind = 1 : i32}, %private: !epochref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge_iff posedge %clk iff %guard to ^body : !bitref, !bitref
    ^body:
      %one = arith.constant 1 : i64
      simulation.ref.store %one to %private : i64, !epochref
      cf.br ^wait
    }
    simulation.func private @change(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %changed: !bitref {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %changed to ^wait : !bitref
    }
  }
}
