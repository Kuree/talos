// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion))' | FileCheck %s

// IEEE 1800-2023 13.5.2: the task's ref formal writes its actual q. A task
// call is a scheduling edge, so its immediate write is absent from the
// caller's summary. It must still enter the source writer inventory: capture
// equality cannot justify dropping an NBA if a blocking writer may intervene
// before commit (4.3, 4.9.4). The clk toggler and the task write roots 0 and 1.
// CHECK-LABEL: simulation.design @design
// CHECK-SAME: schedule.nba.immediate_writers = array<i64: 0, 1>

!clk = !simulation.ref<i1>
!q = !simulation.ref<i8>
module {
  simulation.design @design {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "toggler"
    simulation.code_unit.decl 3 in 0 always hierarchy "clocked"
    simulation.code_unit.decl 4 in 0 task hierarchy "mutate"
    simulation.code_unit.decl 5 in 0 initial hierarchy "caller"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !q
      %a = simulation.spawn @toggler(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %b = simulation.spawn @clocked(%ctx, %clk, %q) : !simulation.context, !clk, !q -> !simulation.process
      %c = simulation.spawn @caller(%ctx, %q) : !simulation.context, !q -> !simulation.process
      simulation.return
    }
    simulation.func private @toggler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %five = simulation.time.constant 5
      simulation.suspend.delay %five to ^body
    ^body:
      %v = simulation.ref.load %clk : !clk -> i1
      %t = arith.constant true
      %n = arith.xori %v, %t : i1
      simulation.ref.store %n to %clk : i1, !clk
      cf.br ^wait
    }
    simulation.func private @clocked(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !q {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !clk
    ^body:
      %v = simulation.ref.load %q : !q -> i8
      %one = arith.constant 1 : i8
      %n = arith.addi %v, %one : i8
      simulation.nba.enqueue %n to %q : (i8, !q) -> ()
      cf.br ^wait
    }
    simulation.func private @mutate(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %dest: !q {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 4 : i64} {
      %one = simulation.time.constant 1
      simulation.suspend.delay %one to ^body
    ^body:
      %c = arith.constant 42 : i8
      simulation.ref.store %c to %dest : i8, !q
      simulation.return
    }
    simulation.func private @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !q {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %six = simulation.time.constant 6
      simulation.suspend.delay %six to ^call
    ^call:
      simulation.task.call @mutate(%ctx, %q) arguments 2 to ^done : !simulation.context, !q
    ^done:
      simulation.return
    }
  }
}
