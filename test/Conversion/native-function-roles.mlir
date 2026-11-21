// RUN: talos-opt %s --finalize-native-functions | FileCheck %s

// Native function finalization reads each function's schedule.eval.role, not
// its symbol: an eval body of a fused compute kernel is 64-byte aligned, and the
// clocked-kernel and eval-body roles become the LLVM function attributes that
// the LLVM layout and outlining passes read. Names below deliberately say
// nothing about roles.

// CHECK-LABEL: llvm.func @clocked_body()
// CHECK-SAME: attributes {passthrough = ["schedule.clocked_kernel", "schedule.eval_body"],
// CHECK-LABEL: llvm.func @fused_body()
// CHECK-SAME: attributes {alignment = 64 : i64, passthrough = ["schedule.eval_body"],
// CHECK-LABEL: llvm.func @fused_kernel()
// CHECK-SAME: attributes {schedule.eval.role
// CHECK-LABEL: llvm.func @spawn_helper()
// CHECK-SAME: attributes {passthrough = ["noinline", "schedule.clocked_kernel"],
// CHECK-LABEL: llvm.func @__talos_clocked_0_0.__talos_eval_body_0() {
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.func @clocked_body() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel|eval_body>} {
    llvm.return
  }
  llvm.func @fused_body() attributes {schedule.eval.role = #schedule.eval_role<fused_kernel|eval_body>} {
    llvm.return
  }
  llvm.func @fused_kernel() attributes {schedule.eval.role = #schedule.eval_role<fused_kernel>} {
    llvm.return
  }
  llvm.func @spawn_helper() attributes {passthrough = ["noinline"], schedule.eval.role = #schedule.eval_role<clocked_kernel|spawn_helper>} {
    llvm.return
  }
  llvm.func @__talos_clocked_0_0.__talos_eval_body_0() {
    llvm.return
  }
}
