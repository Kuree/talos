// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true}))' | FileCheck %s

// always_comb latch: q only changes when en is high, so q is a may-write, and
// latch is its only writer. The statement slice order runs comb_y's read of q
// after the latch's write. Like an always_comb, whose implicit sensitivity
// excludes what the block itself writes (IEEE 1800-2023 9.2.2.2.1(b)), the
// fused kernel waits on a, en and b but not on q; waiting on q would wake it
// again on its own held output.
// CHECK-LABEL: simulation.design @exclusive_may_write
// CHECK: simulation.func private @__talos_region_kernel_{{[0-9_]+}}(
// CHECK-DAG: %[[A:.+]] = simulation.context.storage %arg0[0]
// CHECK-DAG: %[[EN:.+]] = simulation.context.storage %arg0[1]
// CHECK-DAG: %[[B:.+]] = simulation.context.storage %arg0[3]
// CHECK: simulation.suspend.any %[[B]], %[[A]], %[[EN]] edges [0, 0, 0] to

!r = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @exclusive_may_write {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "latch"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "comb_y"
    simulation.code_unit.decl 3 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @latch(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @comb_y(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // always_comb if (en) q = a;
    simulation.func @latch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %en = simulation.context.storage %ctx[1] : !r
      %q = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %e = simulation.ref.load %en : !r -> i1
      cf.cond_br %e, ^capture, ^wait
    ^capture:
      %value = simulation.ref.load %a : !r -> i1
      simulation.ref.store %value to %q : i1, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %en edges [0, 0] to ^body : !r, !r
    }
    // always_comb y = q ^ b;
    simulation.func @comb_y(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %q = simulation.context.storage %ctx[2] : !r
      %b = simulation.context.storage %ctx[3] : !r
      %y = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %qv = simulation.ref.load %q : !r -> i1
      %bv = simulation.ref.load %b : !r -> i1
      %yv = arith.xori %qv, %bv : i1
      simulation.ref.store %yv to %y : i1, !r
      simulation.suspend.any %q, %b edges [0, 0] to ^body : !r, !r
    }
    // Keeps q and y live.
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %q = simulation.context.storage %ctx[2] : !r
      %y = simulation.context.storage %ctx[4] : !r
      %one = simulation.time.constant 1
      %format = simulation.bytes.constant "q=%0d y=%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %one to ^sample
    ^sample:
      %qv = simulation.ref.load %q : !r -> i1
      %yv = simulation.ref.load %y : !r -> i1
      simulation.display %ctx to %stdout(%format, %qv, %yv) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.return
    }
  }
}

// -----

// The latch writes only q[0]; an initial process writes q[1]. Only the
// latch's own bit leaves the wait: the kernel still wakes on q[1], a, en and
// b.
// CHECK-LABEL: simulation.design @partial
// CHECK: simulation.func private @__talos_region_kernel_{{[0-9_]+}}(
// CHECK-DAG: %[[Q:.+]] = simulation.context.storage %arg0[2]
// CHECK-DAG: %[[Q1:.+]] = simulation.ref.extract %[[Q]] from 1
// CHECK-DAG: %[[B:.+]] = simulation.context.storage %arg0[3]
// CHECK-DAG: %[[A:.+]] = simulation.context.storage %arg0[0]
// CHECK-DAG: %[[EN:.+]] = simulation.context.storage %arg0[1]
// CHECK: simulation.suspend.any %[[Q1]], %[[B]], %[[A]], %[[EN]] edges [0, 0, 0, 0] to

!r = !simulation.ref<i1>
!r2 = !simulation.ref<i2>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @partial {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i2 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "latch"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "comb_y"
    simulation.code_unit.decl 3 in 0 initial hierarchy "check"
    simulation.code_unit.decl 4 in 0 initial hierarchy "poke"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @latch(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @comb_y(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @poke(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // always_comb if (en) q[0] = a;
    simulation.func @latch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %en = simulation.context.storage %ctx[1] : !r
      %q = simulation.context.storage %ctx[2] : !r2
      %q0 = simulation.ref.extract %q from 0 : !r2 -> !r
      cf.br ^body
    ^body:
      %e = simulation.ref.load %en : !r -> i1
      cf.cond_br %e, ^capture, ^wait
    ^capture:
      %value = simulation.ref.load %a : !r -> i1
      simulation.ref.store %value to %q0 : i1, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %en edges [0, 0] to ^body : !r, !r
    }
    // always_comb y = ^q ^ b;
    simulation.func @comb_y(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %q = simulation.context.storage %ctx[2] : !r2
      %b = simulation.context.storage %ctx[3] : !r
      %y = simulation.context.storage %ctx[4] : !r
      %q0 = simulation.ref.extract %q from 0 : !r2 -> !r
      %q1 = simulation.ref.extract %q from 1 : !r2 -> !r
      cf.br ^body
    ^body:
      %v0 = simulation.ref.load %q0 : !r -> i1
      %v1 = simulation.ref.load %q1 : !r -> i1
      %bv = simulation.ref.load %b : !r -> i1
      %x = arith.xori %v0, %v1 : i1
      %yv = arith.xori %x, %bv : i1
      simulation.ref.store %yv to %y : i1, !r
      simulation.suspend.any %q, %b edges [0, 0] to ^body : !r2, !r
    }
    // initial #1 q[1] = 1;
    simulation.func @poke(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %q = simulation.context.storage %ctx[2] : !r2
      %q1 = simulation.ref.extract %q from 1 : !r2 -> !r
      %one = simulation.time.constant 1
      simulation.suspend.delay %one to ^go
    ^go:
      %t = arith.constant true
      simulation.ref.store %t to %q1 : i1, !r
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %y = simulation.context.storage %ctx[4] : !r
      %two = simulation.time.constant 2
      %format = simulation.bytes.constant "y=%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %two to ^sample
    ^sample:
      %yv = simulation.ref.load %y : !r -> i1
      simulation.display %ctx to %stdout(%format, %yv) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i1
      simulation.return
    }
  }
}
