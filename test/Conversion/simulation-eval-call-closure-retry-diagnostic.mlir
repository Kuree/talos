// RUN: not talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines 2>&1 | FileCheck %s
// RUN: talos-opt %s --emit-bytecode -o %t.bc
// RUN: not talos-opt %t.bc --convert-talos-sim-processes-to-llvm-coroutines 2>&1 | FileCheck %s

// Automatic native selection preserves the retry contract while timing mode
// explains which call prevented a closed eval activation.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  native.debug_timing,
  schedule.eval.closure_retry_allowed,
  schedule.eval.generated
} {
  llvm.func @talos_rt_forbidden()
  llvm.func @__talos_eval_rejected() attributes {
      schedule.eval.call_closure_root
  } {
    llvm.call @talos_rt_forbidden() : () -> ()
    llvm.return
  }
}

// CHECK: talos native eval closure rejection: generated eval hot closure calls runtime symbol talos_rt_forbidden in __talos_eval_rejected
