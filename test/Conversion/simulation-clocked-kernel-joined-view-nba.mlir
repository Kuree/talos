// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' | FileCheck %s

// IEEE 1800-2023 7.2.1, 10.4.2, 11.5.1: selecting either packed byte before
// capturing an indexed NBA retains that byte's boundary. Joining the two
// references gives a whole-root may-select range, not a whole-root view, so
// its narrower type and nonconstant address keep the clipped NBA. The
// independent whole-byte sibling still becomes a direct store.
// CHECK-LABEL: simulation.func private @{{__talos_clocked_[0-9_]+}}(
// CHECK: ^{{bb[0-9]+}}(%[[PARENT:.*]]: !simulation.ref<i8>):
// CHECK: %[[PART:.*]] = simulation.ref.dyn_extract %[[PARENT]] from
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.nba.enqueue %{{.*}} to %[[PART]]
// CHECK: simulation.ref.store %{{.*}} to %{{.*}} {schedule.eval.nba_equivalent_store}

!bit = !simulation.ref<i1>
!word = !simulation.ref<i16>
!byte = !simulation.ref<i8>
!index = !simulation.ref<i64>
simulation.design @joined_member {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : i1 design
  simulation.storage.decl 1 in 0 : i16 design
  simulation.storage.decl 2 in 0 : i8 design
  simulation.storage.decl 3 in 0 : i1 design
  simulation.storage.decl 4 in 0 : i64 design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always hierarchy "member"
  simulation.code_unit.decl 4 in 0 always hierarchy "sibling"
  simulation.code_unit.decl 5 in 0 initial hierarchy "reader"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !bit
    %q = simulation.context.storage %ctx[1] : !word
    %r = simulation.context.storage %ctx[2] : !byte
    %choice = simulation.context.storage %ctx[3] : !bit
    %idx = simulation.context.storage %ctx[4] : !index
    %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !bit -> !simulation.process
    %w = simulation.spawn @member(%ctx, %clk, %q, %choice, %idx) : !simulation.context, !bit, !word, !bit, !index -> !simulation.process
    %s = simulation.spawn @sibling(%ctx, %clk, %r) : !simulation.context, !bit, !byte -> !simulation.process
    %o = simulation.spawn @reader(%ctx, %q, %r) : !simulation.context, !word, !byte -> !simulation.process
    simulation.return
  }
  simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !bit {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
    %delay = simulation.time.constant 5
    %one = arith.constant true
    simulation.suspend.delay %delay to ^toggle
  ^toggle:
    %v = simulation.ref.load %clk : !bit -> i1
    %n = arith.xori %v, %one : i1
    simulation.ref.store %n to %clk : i1, !bit
    simulation.suspend.delay %delay to ^toggle
  }
  simulation.func private @member(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !bit {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !word {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %choice: !bit {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %idx: !index {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body : !bit
  ^body:
    %choose = simulation.ref.load %choice : !bit -> i1
    cf.cond_br %choose, ^left, ^right
  ^left:
    %lo = simulation.ref.extract %q from 0 : !word -> !byte
    cf.br ^write(%lo : !byte)
  ^right:
    %hi = simulation.ref.extract %q from 8 : !word -> !byte
    cf.br ^write(%hi : !byte)
  ^write(%selected: !byte):
    %index = simulation.ref.load %idx : !index -> i64
    %part = simulation.ref.dyn_extract %selected from %index : (!byte, i64) -> !simulation.ref<i4>
    %value = arith.constant 15 : i4
    simulation.nba.enqueue %value to %part : (i4, !simulation.ref<i4>) -> ()
    cf.br ^wait
  }
  simulation.func private @sibling(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !bit {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %r: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body : !bit
  ^body:
    %value = arith.constant 42 : i8
    simulation.nba.enqueue %value to %r : (i8, !byte) -> ()
    cf.br ^wait
  }
  simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !word {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
    %delay = simulation.time.constant 100
    simulation.suspend.delay %delay to ^read
  ^read:
    %qv = simulation.ref.load %q : !word -> i16
    %rv = simulation.ref.load %r : !byte -> i8
    simulation.return
  }
}
