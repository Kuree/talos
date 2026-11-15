// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// An Inactive (#0) reset writer may run on either side of a deferred kernel, so
// the member could read different reset values (IEEE 1800-2023 4.4.2.3, 4.5).
// CHECK-LABEL: simulation.design @inactive_reset
// CHECK-NOT: __talos_clocked_
// CHECK: simulation.nba.enqueue
// CHECK: simulation.nba.enqueue
// CHECK-NOT: __talos_clocked_
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @inactive_reset {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %rst = simulation.context.storage %ctx[2] : !r
    %p0 = simulation.spawn @clock(%ctx, %clk, %rst) : !simulation.context, !r, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %clk, %rst, %q0) : !simulation.context, !r, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    %zero = simulation.time.constant 0
    %v = simulation.logic.constant true, false : !b
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %c = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %c : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
    simulation.suspend.delay %zero to ^write
  ^write:
    simulation.ref.store %v to %rst : !b, !r
    simulation.suspend.delay %d to ^toggle
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %clk, %rst edges [1, 2] to ^body : !r, !r
  ^body:
    %reset = simulation.ref.load %rst : !r -> !b
    %run = simulation.logic.is_true %reset : !b
    cf.cond_br %run, ^update, ^reset
  ^reset:
    %zero = simulation.logic.constant false, false : !b
    simulation.nba.enqueue %zero to %q : (!b, !r) -> ()
    cf.br ^wait
  ^update:
    %old = simulation.ref.load %q : !r -> !b
    %one = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %one to %q : (!b, !r) -> ()
    cf.br ^wait
  }
}

// -----
// A watched reset is protected even if no member reads it: clock, q<=~q,
// #0 reset, q<=~q must not read the old q twice (IEEE 1800-2023 4.5, 9.4.2).
// CHECK-LABEL: simulation.design @inactive_unread_reset
// CHECK-NOT: __talos_clocked_
// CHECK: simulation.nba.enqueue
// CHECK-NOT: __talos_clocked_
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @inactive_unread_reset {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %rst = simulation.context.storage %ctx[2] : !r
    %one = simulation.logic.constant true, false : !b
    simulation.ref.store %one to %rst : !b, !r
    %p0 = simulation.spawn @clock(%ctx, %clk, %rst) : !simulation.context, !r, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %clk, %rst, %q0) : !simulation.context, !r, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    %zero = simulation.time.constant 0
    %v = simulation.logic.constant false, false : !b
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %c = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %c : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
    simulation.suspend.delay %zero to ^write
  ^write:
    simulation.ref.store %v to %rst : !b, !r
    simulation.suspend.delay %d to ^toggle
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %clk, %rst edges [1, 2] to ^body : !r, !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
}

