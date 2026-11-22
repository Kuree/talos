// RUN: talos-opt %s --materialize-native-eval-transactions --verify-diagnostics -o /dev/null

// A lowering pass run on its own reuses a predeclared runtime entry and
// reports one that does not use the C calling convention, the convention
// the runtime library defines its entries with. (The native pipeline rejects
// it on entry: simulation-runtime-declarations-invalid.mlir.)
module attributes {schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.func @talos_rt_v1_scheduler_prepare_eval_nba(!llvm.ptr, !llvm.ptr) -> i32
  // expected-error @+1 {{runtime symbol @talos_rt_v1_scheduler_prepare_quiet_eval_nba is predeclared with the fastcc calling convention; runtime entries use the C calling convention}}
  llvm.func fastcc @talos_rt_v1_scheduler_prepare_quiet_eval_nba(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @__talos_clocked_a() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.return
  }
  llvm.func @__talos_clocked_b() attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel>} {
    llvm.return
  }
  llvm.func @__talos_eval_dispatch_v1(%ctx: !llvm.ptr, %out: !llvm.ptr) {
    %s0 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_a() : () -> ()
    %s1 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.call @__talos_clocked_b() : () -> ()
    %s2 = llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
}
