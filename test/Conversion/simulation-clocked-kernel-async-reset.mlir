// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=false}))' | FileCheck %s --check-prefix=IMMEDIATE --implicit-check-not=__talos_clocked_

// IEEE 1800-2023 4.5, 9.4.2, 10.4.2: matching multi-edge controls stay one
// wait with each member's reset branch; the opposite-polarity (third) and
// other-reset (fourth) members are different controls with their own kernels.
// IMMEDIATE-LABEL: simulation.design @async_reset
// IMMEDIATE: simulation.suspend.any
// IMMEDIATE: simulation.nba.enqueue
// CHECK-LABEL: simulation.design @async_reset
// CHECK-COUNT-3: simulation.spawn @__talos_clocked_
// CHECK-NOT: simulation.spawn @__talos_clocked_
// CHECK: simulation.suspend.any %{{.*}}, %{{.*}} edges [1, 2] to ^{{.*}} {resume_region = 3 : i32,
// CHECK: simulation.logic.is_true
// CHECK: cf.cond_br
// CHECK: simulation.ref.store
// CHECK: simulation.logic.is_true
// CHECK: cf.cond_br
// CHECK: simulation.ref.store
// CHECK-NOT: simulation.nba.enqueue
// CHECK: simulation.suspend.any %{{.*}}, %{{.*}} edges [1, 1]
// CHECK: simulation.suspend.any %{{.*}}, %{{.*}} edges [1, 2]
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @async_reset {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.storage.decl 4 in 0 : !b design
  simulation.storage.decl 5 in 0 : !b design
  simulation.storage.decl 6 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.code_unit.decl 4 in 0 always_ff hierarchy "second"
  simulation.code_unit.decl 5 in 0 always_ff hierarchy "third"
  simulation.code_unit.decl 6 in 0 always_ff hierarchy "fourth"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %q1 = simulation.context.storage %ctx[2] : !r
    %rst = simulation.context.storage %ctx[3] : !r
    %q2 = simulation.context.storage %ctx[5] : !r
    %q3 = simulation.context.storage %ctx[6] : !r
    %rst2 = simulation.context.storage %ctx[4] : !r
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %clk, %rst, %q0) : !simulation.context, !r, !r, !r -> !simulation.process
    %p2 = simulation.spawn @second(%ctx, %clk, %rst, %q1) : !simulation.context, !r, !r, !r -> !simulation.process
    %p3 = simulation.spawn @third(%ctx, %clk, %rst, %q2) : !simulation.context, !r, !r, !r -> !simulation.process
    %p4 = simulation.spawn @fourth(%ctx, %clk, %rst2, %q3) : !simulation.context, !r, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %v = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
    simulation.suspend.delay %d to ^toggle
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
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
  simulation.func private @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %rst, %clk edges [2, 1] to ^body : !r, !r
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
  simulation.func private @third(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %clk, %rst edges [1, 1] to ^body : !r, !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
  simulation.func private @fourth(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
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

// -----
// A member's blocking write to the reset wakes another activation in the
// same phase (IEEE 1800-2023 4.5): no kernel, and the NBA stays.
// CHECK-LABEL: simulation.design @reset_feedback
// CHECK-NOT: __talos_clocked_
// CHECK: simulation.nba.enqueue
// CHECK-NOT: __talos_clocked_
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @reset_feedback {
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
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %clk, %rst, %q0) : !simulation.context, !r, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %v = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
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
    simulation.ref.store %one to %rst : !b, !r
    cf.br ^wait
  }
}

