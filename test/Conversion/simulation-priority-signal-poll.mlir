// RUN: talos-opt %s --materialize-native-eval-transactions -o %t.mlir
// RUN: FileCheck %s < %t.mlir

// A disarmed waiter costs no slow query. The next owner publishes a priority
// wake, then the following one disarms it. Each poll observes the state at
// its own boundary (1800-2023 4.5, 16.12).
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: %[[FLAG:.*]] = llvm.call @talos_rt_v1_scheduler_priority_signal_flag(
// CHECK: llvm.load %[[FLAG]]
// CHECK: llvm.cond_br
// CHECK: llvm.call @talos_rt_v1_scheduler_priority_signal_pending(
// CHECK: llvm.load %[[FLAG]]
// CHECK: llvm.load %[[FLAG]]
module attributes {schedule.eval.runtime_calendar, schedule.eval.assertion_observers = true} {
  llvm.func @talos_rt_v1_scheduler_priority_signal_flag(!llvm.ptr) -> !llvm.ptr
  llvm.func @talos_rt_v1_scheduler_priority_signal_pending(!llvm.ptr) -> i32
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr) -> i32 attributes {schedule.eval.role = #schedule.eval_role<dispatch>} {
    %a = llvm.call @talos_rt_v1_scheduler_priority_signal_pending(%ctx) : (!llvm.ptr) -> i32
    %one = llvm.mlir.constant(1 : i8) : i8
    llvm.store %one, %ctx : i8, !llvm.ptr
    %b = llvm.call @talos_rt_v1_scheduler_priority_signal_pending(%ctx) : (!llvm.ptr) -> i32
    %zero = llvm.mlir.constant(0 : i8) : i8
    llvm.store %zero, %ctx : i8, !llvm.ptr
    %c = llvm.call @talos_rt_v1_scheduler_priority_signal_pending(%ctx) : (!llvm.ptr) -> i32
    %sum = llvm.add %a, %b : i32
    %total = llvm.add %sum, %c : i32
    llvm.return %total : i32
  }
}
