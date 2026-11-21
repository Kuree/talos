// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 12 : i64}"},talos-materialize-native-eval-groups)' | FileCheck %s --check-prefix=FITS
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 11 : i64}"},talos-materialize-native-eval-groups)' | FileCheck %s --check-prefix=OVER

// An eval mask word access names its mask. The inline budget charges it as
// its LLVM form: the access, a byte GEP to word 1, and the mask's address
// once per function. The producer costs 8 (its constant, two word accesses
// of two operations each, the OR, its return and the address), the consumer
// 4. Both fit 12 operations; at 11 the consumer stays a call. An inlined
// access keeps its member as its owner.
// FITS-LABEL: llvm.func @group()
// FITS-SAME: schedule.eval.materialized_group_calls = 2
// FITS: %[[OLD:.*]] = schedule.mask.load @__talos_eval_step_four_state_nba_roots_v1[1] {owner = 0 : i32}
// FITS: schedule.mask.store %{{.*}}, @__talos_eval_step_four_state_nba_roots_v1[1] {owner = 0 : i32}
// FITS-NOT: llvm.call
// FITS: llvm.return
// OVER-LABEL: llvm.func @group()
// OVER-SAME: schedule.eval.materialized_group_calls = 1
// OVER: llvm.call @consumer()
module {
  llvm.mlir.global internal @__talos_eval_step_four_state_nba_roots_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.func @producer() attributes {schedule.eval.infallible} {
    %bits = llvm.mlir.constant(2 : i64) : i64
    %old = schedule.mask.load @__talos_eval_step_four_state_nba_roots_v1[1]
    %new = llvm.or %old, %bits : i64
    schedule.mask.store %new, @__talos_eval_step_four_state_nba_roots_v1[1]
    llvm.return
  }
  llvm.func @consumer() attributes {schedule.eval.infallible} {
    %out = llvm.mlir.addressof @observed : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %out : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @producer() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @consumer() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
}
