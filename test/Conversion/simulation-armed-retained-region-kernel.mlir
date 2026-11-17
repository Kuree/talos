// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false interleave-rearms=true}))' | FileCheck %s --implicit-check-not='spawn @a_latch('

// The latch keeps q while en is low, so it retains state. A region kernel
// runs once at startup, as always_comb does "once at time zero, after all
// initial and always procedures have been started" (IEEE 1800-2023
// 9.2.2.2). A retained `always @(list)` member must not, because it "waits
// until a change occurs" (9.2.2.2.2, 9.4.2). The armed form tests its bit
// before the body, and only its arming copy sets the bit at that first event,
// so a startup run leaves q untouched and the latch may join the kernel. The
// always_comb members stay outside the guard and still run at startup.
// a_latch sorts first among the members, yet the kernel takes comb_y as its
// always_comb owner. @check only keeps z live.
// CHECK: simulation.spawn @a_latch_arm(
// CHECK-NEXT: simulation.spawn @[[KERNEL:__talos_region_kernel_[0-9_]+]](
// CHECK: simulation.func private @[[KERNEL]](
// CHECK-SAME: code_unit_id = 3 : i64
// CHECK-SAME: entry_kind = 4 : i32
// CHECK-DAG: %[[Q:.+]] = simulation.context.storage %arg0[2]
// CHECK-DAG: %[[ARMED:.+]] = simulation.context.storage %arg0[6]
// CHECK: ^[[ENTRY:bb[0-9]+]]:
// CHECK-NEXT: %[[SET:.+]] = simulation.ref.load %[[ARMED]]
// CHECK-NEXT: cf.cond_br %[[SET]], ^[[BODY:bb[0-9]+]], ^[[REST:bb[0-9]+]]
// CHECK: ^[[BODY]]:
// CHECK: simulation.ref.store %{{.+}} to %[[Q]]
// CHECK: ^[[REST]]:
// CHECK: %[[Z:.+]] = simulation.context.storage %arg0[5]
// CHECK: simulation.ref.store %{{.+}} to %[[Z]]
// CHECK: simulation.suspend.any {{.*}}%[[ARMED]]{{[, ]}}{{.*}} to ^[[ENTRY]]

!r = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @armed_retained {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.storage.decl 6 in 0 : i1 design {observability = 0 : i32}
    simulation.code_unit.decl 1 in 0 always hierarchy "a_latch"
    simulation.code_unit.decl 2 in 0 initial hierarchy "a_latch.$arm" {internal}
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "comb_y"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "comb_z"
    simulation.code_unit.decl 5 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @a_latch(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @a_latch_arm(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @comb_y(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @comb_z(%ctx) : !simulation.context -> !simulation.process
      %p4 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // always @(a or en) if (en) q = a; after the armed rewrite.
    simulation.func @a_latch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64, schedule.armed_combinational} {
      %a = simulation.context.storage %ctx[0] : !r
      %en = simulation.context.storage %ctx[1] : !r
      %q = simulation.context.storage %ctx[2] : !r
      %armed = simulation.context.storage %ctx[6] : !r
      cf.br ^guard
    ^wait:
      simulation.suspend.any %a, %en, %armed edges [0, 0, 0] to ^guard {schedule.procedural_event_wait, schedule.repeating_always_wait} : !r, !r, !r
    ^guard:
      %set = simulation.ref.load %armed : !r -> i1
      cf.cond_br %set, ^body, ^wait
    ^body:
      %e = simulation.ref.load %en : !r -> i1
      cf.cond_br %e, ^capture, ^wait
    ^capture:
      %value = simulation.ref.load %a : !r -> i1
      simulation.ref.store %value to %q : i1, !r
      cf.br ^wait
    }
    simulation.func @a_latch_arm(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %en = simulation.context.storage %ctx[1] : !r
      %armed = simulation.context.storage %ctx[6] : !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %en edges [0, 0] to ^set {schedule.procedural_event_wait} : !r, !r
    ^set:
      %true = arith.constant true
      simulation.ref.store %true to %armed : i1, !r
      simulation.return
    }
    // always_comb y = q ^ b;
    simulation.func @comb_y(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
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
    // always_comb z = ~y;
    simulation.func @comb_z(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %y = simulation.context.storage %ctx[4] : !r
      %z = simulation.context.storage %ctx[5] : !r
      %one = arith.constant true
      cf.br ^body
    ^body:
      %yv = simulation.ref.load %y : !r -> i1
      %zv = arith.xori %yv, %one : i1
      simulation.ref.store %zv to %z : i1, !r
      simulation.suspend.change %y to ^body : !r
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %q = simulation.context.storage %ctx[2] : !r
      %z = simulation.context.storage %ctx[5] : !r
      %one = simulation.time.constant 1
      %format = simulation.bytes.constant "q=%0d z=%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %one to ^sample
    ^sample:
      %qv = simulation.ref.load %q : !r -> i1
      %zv = simulation.ref.load %z : !r -> i1
      simulation.display %ctx to %stdout(%format, %qv, %zv) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      simulation.return
    }
  }
}
