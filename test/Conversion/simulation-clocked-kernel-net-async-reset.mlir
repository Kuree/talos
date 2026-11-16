// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=false}))' | FileCheck %s --check-prefix=IMMEDIATE --implicit-check-not=__talos_clocked_

// IEEE 1800-2023 9.4.2, 9.4.2.1: net event expressions behave like variable
// ones; the inverted-net/reset wait keeps its polarity and the driver stays
// its own process.
// IMMEDIATE-LABEL: simulation.design @net_async_reset
// IMMEDIATE: simulation.suspend.any
// CHECK-LABEL: simulation.design @net_async_reset
// CHECK: simulation.spawn @invert
// CHECK: simulation.spawn @[[KERNEL:__talos_clocked_[0-9_]+]]
// CHECK: simulation.func private @invert
// CHECK: simulation.driver.drive
// CHECK: simulation.func private @[[KERNEL]]
// CHECK: simulation.suspend.any %{{.*}}, %{{.*}} edges [1, 2] to ^{{.*}} {resume_region = 3 : i32,
// CHECK-SAME: : !simulation.net<!simulation.logic<1>>, !simulation.ref<!simulation.logic<1>>
// CHECK: simulation.ref.store
// CHECK-NOT: simulation.nba.enqueue
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
!n = !simulation.net<!b>
!d = !simulation.driver<!b>
simulation.design @net_async_reset {
  simulation.scope.decl 0
  simulation.net.decl 0 in 0 : !b design
  simulation.driver.decl 0 in 0 drives 0 : !b design
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "invert"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %rst = simulation.context.storage %ctx[2] : !r
    %net = simulation.context.net %ctx[0] : !n
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p1 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
    %p2 = simulation.spawn @first(%ctx, %net, %rst, %q0) : !simulation.context, !n, !r, !r -> !simulation.process
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
  simulation.func private @invert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    %src = simulation.context.storage %ctx[0] : !r
    %driver = simulation.context.driver %ctx[0] : !d
    cf.br ^copy
  ^copy:
    %v = simulation.ref.load %src : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.driver.drive %driver = %n : !d, !b
    simulation.suspend.change %src to ^copy : !r
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !n {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %clk, %rst edges [1, 2] to ^body : !n, !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
}

// -----
// An NBA that feeds its own watched net keeps its NBA publication; the other
// private root may still use a direct store.
// CHECK-LABEL: simulation.design @net_feedback
// CHECK: simulation.func private @__talos_clocked_
// CHECK: simulation.suspend.any
// CHECK: simulation.nba.enqueue
// CHECK: simulation.ref.store
// IMMEDIATE-LABEL: simulation.design @net_feedback
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
!n = !simulation.net<!b>
!d = !simulation.driver<!b>
simulation.design @net_feedback {
  simulation.scope.decl 0
  simulation.net.decl 0 in 0 : !b design
  simulation.driver.decl 0 in 0 drives 0 : !b design
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.storage.decl 3 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.code_unit.decl 4 in 0 always_ff hierarchy "second"
  simulation.code_unit.decl 5 in 0 continuous hierarchy "invert"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %q1 = simulation.context.storage %ctx[2] : !r
    %rst = simulation.context.storage %ctx[3] : !r
    %net = simulation.context.net %ctx[0] : !n
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p1 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
    %p2 = simulation.spawn @first(%ctx, %net, %rst, %q0) : !simulation.context, !n, !r, !r -> !simulation.process
    %p3 = simulation.spawn @second(%ctx, %net, %rst, %q1) : !simulation.context, !n, !r, !r -> !simulation.process
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
  simulation.func private @invert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
    %src = simulation.context.storage %ctx[1] : !r
    %driver = simulation.context.driver %ctx[0] : !d
    cf.br ^copy
  ^copy:
    %v = simulation.ref.load %src : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.driver.drive %driver = %n : !d, !b
    simulation.suspend.change %src to ^copy : !r
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !n {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %clk, %rst edges [1, 2] to ^body : !n, !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
  simulation.func private @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !n {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %rst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.any %rst, %clk edges [2, 1] to ^body : !r, !n
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
}

