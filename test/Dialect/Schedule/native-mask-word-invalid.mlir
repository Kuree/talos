// RUN: talos-opt %s --split-input-file --verify-diagnostics

// A ready set is no eval mask.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{names '__talos_aot_model_ingress_v1', no generated eval mask}}
    %word = schedule.mask.load @__talos_aot_model_ingress_v1[0]
    llvm.return %word : i64
  }
}

// -----
module {
  llvm.func @bad(%bits: i64) {
    // expected-error @+1 {{must reference the llvm.mlir.global of its mask, an array of i64 words}}
    schedule.mask.store %bits, @__talos_eval_fast_nba_roots_v1[0]
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_step_four_state_nba_roots_v1(0 : i64) : i64
  llvm.func @bad(%bits: i64) {
    // expected-error @+1 {{must reference the llvm.mlir.global of its mask, an array of i64 words}}
    schedule.mask.store %bits, @__talos_eval_step_four_state_nba_roots_v1[0]
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%word: i64) -> i64 {
    // expected-error @+1 {{accesses word 2 of a mask of 2 words}}
    %bits = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[%word + 2]
    llvm.return %bits : i64
  }
}

// -----
// A static word is unsigned: -1 names word 2^64 - 1, past the end of any
// mask, not the word before it.
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{accesses word 18446744073709551615 of a mask of 2 words}}
    %word = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[-1]
    llvm.return %word : i64
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad(%bits: i64) {
    // expected-error @+1 {{accesses word 18446744073709551615 of a mask of 2 words}}
    schedule.mask.store %bits, @__talos_eval_promotion_pending_mask_v1[-1]
    llvm.return
  }
}

// -----
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @bad() -> i64 {
    // expected-error @+1 {{carries the schedule fact 'schedule.eval.group_owner' as a property, not an attribute}}
    %bits = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0] {schedule.eval.group_owner = 0 : i32}
    llvm.return %bits : i64
  }
}

// -----
// A global's initializer accesses no mask word.
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @outside() : i64 {
    // expected-error @below {{must be in a function}}
    %bits = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
    llvm.return %bits : i64
  }
}
