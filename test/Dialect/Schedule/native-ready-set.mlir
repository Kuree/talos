// RUN: talos-opt %s | talos-opt | FileCheck %s

// Ready actions name a generated eval ready set by its global and the leaf
// word they access; a merge adds a whole bitmap to the set.
// CHECK-LABEL: llvm.func @actions(
// CHECK-SAME: %[[MASK:.*]]: i64, %[[SOURCE:.*]]: !llvm.ptr)
// CHECK: schedule.ready.update @__talos_aot_model_ingress_v1[1], %[[MASK]] {capacity = 128 : i64, consume = false}
// CHECK: schedule.ready.commit @__talos_eval_nba_held_wakes_v1[0], %[[MASK]], %[[MASK]] {capacity = 128 : i64}
// CHECK: schedule.ready.merge @__talos_aot_model_ingress_v1, %[[SOURCE]] {capacity = 128 : i64}
// CHECK: %[[WORD:.*]] = schedule.ready.read @__talos_eval_nba_held_wakes_v1[1] {capacity = 128 : i64}
// CHECK: llvm.return %[[WORD]]
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.func @actions(%mask: i64, %source: !llvm.ptr) -> i64 {
    schedule.ready.update @__talos_aot_model_ingress_v1[1], %mask {capacity = 128 : i64, consume = false}
    schedule.ready.commit @__talos_eval_nba_held_wakes_v1[0], %mask, %mask {capacity = 128 : i64}
    schedule.ready.merge @__talos_aot_model_ingress_v1, %source {capacity = 128 : i64}
    %word = schedule.ready.read @__talos_eval_nba_held_wakes_v1[1] {capacity = 128 : i64}
    llvm.return %word : i64
  }
}
