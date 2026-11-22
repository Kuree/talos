// RUN: talos-opt %s --split-input-file --materialize-native-eval-transactions | FileCheck %s

// A register body keeps the shared view of the generic NBA queue only when
// each call it makes updates at most the queue and its membership words: a
// runtime entry the catalog marks QueueCaptureOnly. A capture qualifies only
// when it is not delayed (operand 6 of scheduler_nba is zero): a delayed
// assignment schedules its update for a later simulation time (1800-2023
// 4.4.2.4, 10.4.2), not in this queue.

// The failure latch is capture-only.
// CHECK-LABEL: llvm.func internal @body.__talos_queue_view(
// CHECK: llvm.call @talos_rt_v1_scheduler_fail(
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: llvm.call @body.__talos_queue_view(
module attributes {schedule.force_generic_nba, schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_generic_nba_words(!llvm.ptr, i32) -> !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i32)
  llvm.func @body(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(2 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %status = llvm.load %view : !llvm.ptr -> i32
    llvm.call @talos_rt_v1_scheduler_fail(%ctx, %status) : (!llvm.ptr, i32) -> ()
    llvm.return
  }
  llvm.func @__talos_aot_schedule_run_v1(%ctx: !llvm.ptr) {
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.return
  }
}

// -----

// Reporting a status is not capture-only: the view is not shared.
// CHECK-LABEL: llvm.func @talos_rt_v1_scheduler_report_status(
// CHECK-NOT: __talos_queue_view
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK-NOT: __talos_queue_view
// CHECK: llvm.return
module attributes {schedule.force_generic_nba, schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_generic_nba_words(!llvm.ptr, i32) -> !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_report_status(!llvm.ptr, i32)
  llvm.func @body(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(2 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %status = llvm.load %view : !llvm.ptr -> i32
    llvm.call @talos_rt_v1_scheduler_report_status(%ctx, %status) : (!llvm.ptr, i32) -> ()
    llvm.return
  }
  llvm.func @__talos_aot_schedule_run_v1(%ctx: !llvm.ptr) {
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.return
  }
}

// -----

// An undelayed generic capture is capture-only.
// CHECK-LABEL: llvm.func internal @body.__talos_queue_view(
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: llvm.call @body.__talos_queue_view(
module attributes {schedule.force_generic_nba, schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_generic_nba_words(!llvm.ptr, i32) -> !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @body(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(2 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %width = llvm.load %view : !llvm.ptr -> i64
    %delay = llvm.mlir.constant(0 : i64) : i64
    %captured = llvm.call @talos_rt_v1_scheduler_nba(%ctx, %view, %view, %width, %width, %width, %delay, %view, %view) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
  llvm.func @__talos_aot_schedule_run_v1(%ctx: !llvm.ptr) {
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.return
  }
}

// -----

// A delayed one is not.
// CHECK-LABEL: llvm.func @talos_rt_v1_scheduler_nba(
// CHECK-NOT: __talos_queue_view
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK-NOT: __talos_queue_view
// CHECK: llvm.return
module attributes {schedule.force_generic_nba, schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.func @talos_rt_v1_scheduler_generic_nba_words(!llvm.ptr, i32) -> !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @body(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(2 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %width = llvm.load %view : !llvm.ptr -> i64
    %delay = llvm.mlir.constant(1 : i64) : i64
    %captured = llvm.call @talos_rt_v1_scheduler_nba(%ctx, %view, %view, %width, %width, %width, %delay, %view, %view) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
  llvm.func @__talos_aot_schedule_run_v1(%ctx: !llvm.ptr) {
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.call @body(%ctx) : (!llvm.ptr) -> ()
    llvm.return
  }
}
