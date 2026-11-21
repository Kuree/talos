// RUN: talos-opt %s | talos-opt | FileCheck %s

// Words of a generated eval mask are read and written whole, at a static word
// or a dynamic one; an access may name its owner.
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @__talos_eval_route_promotion_pending_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_step_four_state_nba_roots_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.mlir.global internal @__talos_eval_fast_nba_roots_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  // CHECK-LABEL: llvm.func @words(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BITS:.*]]: i64)
  llvm.func @words(%word: i64, %bits: i64) -> i64 {
    // CHECK: schedule.mask.load @__talos_eval_promotion_pending_mask_v1[1] {owner = 65 : i32}
    %pending = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[1] {owner = 65 : i32}
    // CHECK: schedule.mask.load @__talos_eval_fast_nba_roots_v1[%[[WORD]] + 2]
    %fast = schedule.mask.load @__talos_eval_fast_nba_roots_v1[%word + 2]
    // CHECK: schedule.mask.store %[[BITS]], @__talos_eval_step_four_state_nba_roots_v1[%[[WORD]]]
    schedule.mask.store %bits, @__talos_eval_step_four_state_nba_roots_v1[%word]
    // CHECK: schedule.mask.store %[[BITS]], @__talos_eval_route_promotion_pending_v1[0] {owner = 1 : i32}
    schedule.mask.store %bits, @__talos_eval_route_promotion_pending_v1[0] {owner = 1 : i32}
    %any = llvm.or %pending, %fast : i64
    llvm.return %any : i64
  }
}
