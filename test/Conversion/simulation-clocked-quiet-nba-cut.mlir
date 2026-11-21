// RUN: talos-opt %s --split-input-file --materialize-native-eval-transactions -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=PATH < %t.mlir

// Register captures can share the Active/Inactive cut. A publication that
// calls outside the closure clears that proof before the next prepare
// (1800-2023 4.4.2.3-4, 4.5).
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: %[[STAMP:.*]] = llvm.alloca
// CHECK: llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
// CHECK: llvm.call @__talos_clocked_a(
// CHECK-NEXT: {{.*}}llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
// CHECK: llvm.store %{{.*}}, %[[STAMP]]
// CHECK-NEXT: llvm.call @publish(
// CHECK: llvm.call @__talos_clocked_b(
// CHECK-NEXT: {{.*}}llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
module attributes {schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @stage(0 : i32) : i32
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_scheduler_prepare_quiet_eval_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @publish(%destination: !llvm.ptr) {
    %x = llvm.mlir.constant(4 : i32) : i32
    llvm.store %x, %destination : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @__talos_clocked_a() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    %stage = llvm.mlir.addressof @stage : !llvm.ptr
    %v = llvm.mlir.constant(3 : i32) : i32
    llvm.store %v, %stage : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @__talos_clocked_b() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    %stage = llvm.mlir.addressof @stage : !llvm.ptr
    %v = llvm.load %stage : !llvm.ptr -> i32
    %step = llvm.mlir.constant(1 : i32) : i32
    %next = llvm.add %v, %step : i32
    llvm.store %next, %stage : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr, %out: !llvm.ptr) {
    %s0 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_a() : () -> ()
    %s1 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @publish(%ctx) : (!llvm.ptr) -> ()
    %s2 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_b() : () -> ()
    %s3 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
}

// -----

// Every pass through the deferred-owner loop still drains runtime Active
// and Inactive and checks for $finish. Select the NBA region once, after
// the last deferred capture. One owner is called through an adapter, and
// another has a conditional publication that invalidates the cut only when
// that branch executes.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: ^bb1:
// CHECK: llvm.call @talos_rt_v1_scheduler_drain_clocked_active
// CHECK: llvm.load
// CHECK: llvm.cond_br
// CHECK: llvm.call @__talos_clocked_conditional.__talos_clock_cut
// CHECK: llvm.call @adapter
// CHECK: llvm.br ^bb1
// CHECK: llvm.call @talos_rt_v1_scheduler_clocked_nba_region
// CHECK: llvm.return
// PATH-LABEL: llvm.func internal @__talos_clocked_conditional.__talos_clock_cut(
// PATH-SAME: %{{arg[0-9]+}}: i1, %{{arg[0-9]+}}: !llvm.ptr, %[[CUT:arg[0-9]+]]: !llvm.ptr
// PATH: llvm.cond_br
// PATH: llvm.store %{{.*}}, %[[CUT]]
// PATH-NEXT: llvm.call @capture
module attributes {schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.func @capture(!llvm.ptr)
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32
  llvm.func @__talos_clocked_conditional(%report: i1, %ptr: !llvm.ptr) attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.cond_br %report, ^print, ^done
  ^print:
    llvm.call @capture(%ptr) : (!llvm.ptr) -> ()
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @__talos_clocked_quiet() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.return
  }
  llvm.func @adapter() {
    llvm.call @__talos_clocked_quiet() : () -> ()
    llvm.return
  }
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr, %pending: !llvm.ptr) -> i32 {
    %one = llvm.mlir.constant(1 : i64) : i64
    %region = llvm.alloca %one x i32 : (i64) -> !llvm.ptr
    llvm.br ^drain
  ^drain:
    %status = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %region) : (!llvm.ptr, !llvm.ptr) -> i32
    %stop = llvm.mlir.constant(-2 : i32) : i32
    %current = llvm.load %region : !llvm.ptr -> i32
    %done = llvm.icmp "eq" %current, %stop : i32
    llvm.cond_br %done, ^exit(%status : i32), ^check
  ^check:
    %active = llvm.load %pending : !llvm.ptr -> i1
    llvm.cond_br %active, ^body, ^commit
  ^body:
    llvm.call @__talos_clocked_conditional(%active, %pending) : (i1, !llvm.ptr) -> ()
    llvm.call @adapter() : () -> ()
    llvm.br ^drain
  ^commit:
    %barrier = llvm.load %region {schedule.eval.nba_barrier_read} : !llvm.ptr -> i32
    llvm.br ^exit(%barrier : i32)
  ^exit(%result: i32):
    llvm.return %result : i32
  }
}

// -----

// An additional user of the region before the final read prevents late
// selection. The checked prepare still returns the actual region to it.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba
// CHECK: llvm.call @observe
// CHECK-NOT: llvm.call @talos_rt_v1_scheduler_clocked_nba_region
// CHECK: llvm.return
module attributes {schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.func @observe(i32)
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32
  llvm.func @__talos_clocked_a() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.return
  }
  llvm.func @__talos_clocked_b() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.return
  }
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr) -> i32 {
    %one = llvm.mlir.constant(1 : i64) : i64
    %region = llvm.alloca %one x i32 : (i64) -> !llvm.ptr
    %status = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %region) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_a() : () -> ()
    %early = llvm.load %region : !llvm.ptr -> i32
    llvm.call @observe(%early) : (i32) -> ()
    llvm.call @__talos_clocked_b() : () -> ()
    %barrier = llvm.load %region {schedule.eval.nba_barrier_read} : !llvm.ptr -> i32
    llvm.return %barrier : i32
  }
}

// -----

// A register body that stages a generated NBA writes only generated storage:
// its accumulator record and its root's dirty-index and summary marks. It
// stays quiet, so every body shares the cut (1800-2023 4.4.2.3-4, 4.5).
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
// CHECK: llvm.call @__talos_clocked_a(
// CHECK-NEXT: {{.*}}llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
// CHECK-NEXT: llvm.call @__talos_clocked_b(
// CHECK-NEXT: {{.*}}llvm.call @talos_rt_v1_scheduler_prepare_quiet_eval_nba(
module attributes {schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @acc0(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @acc1(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_scheduler_prepare_quiet_eval_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @__talos_clocked_a(%v: i64) attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    %r = schedule.nba.acc.address @acc0 : !llvm.ptr
    schedule.nba.acc.store %v, %r[value] {alignment = 8 : i64} : i64
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {root = 0 : i32}
    %bit = llvm.mlir.constant(1 : i64) : i64
    %marked = llvm.or %old, %bit : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 0, 0, 8, 255, 2, 1>, root = 0 : i32}
    %page = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0] {root = 0 : i32}
    %pageBit = llvm.mlir.constant(1 : i64) : i64
    %markedPage = llvm.or %page, %pageBit : i64
    schedule.nba.index.store %markedPage, @__talos_aot_nba_dirty_summary_v1[0] {root = 0 : i32}
    llvm.return
  }
  llvm.func @__talos_clocked_b(%v: i64) attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    %r = schedule.nba.acc.address @acc1 : !llvm.ptr
    schedule.nba.acc.store %v, %r[value] {alignment = 8 : i64} : i64
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[0] {root = 1 : i32}
    %bit = llvm.mlir.constant(2 : i64) : i64
    %marked = llvm.or %old, %bit : i64
    schedule.nba.index.store %marked, @__talos_aot_nba_dirty_roots_v1[0] {capture = array<i64: 1, 1, 8, 255, 2, 2>, root = 1 : i32}
    llvm.return
  }
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr, %out: !llvm.ptr, %v: i64) {
    %s0 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_a(%v) : (i64) -> ()
    %s1 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_b(%v) : (i64) -> ()
    %s2 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
}
