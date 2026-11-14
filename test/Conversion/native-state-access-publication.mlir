// RUN: talos-opt %s --publish-native-proofs | FileCheck %s --implicit-check-not=summary_reported --implicit-check-not=written_bits

// Typed unknown-plane stores report their X/Z changes like LLVM ones (IEEE
// 1800-2023 6.3.1). The first may change only root 1's bits, as its written
// bits declare: the summary marks root 1 (bit 1) itself, and the proof that
// reads root 1 sees its exact change at bit (%d + 32) * 8.
// CHECK-LABEL: llvm.func @writes(
// CHECK-SAME: %[[V:.*]]: i8, %[[D:.*]]: i64)
// CHECK: %[[OLD:.*]] = schedule.state.load @__talos_state_unknown[%[[D]] + 32]
// CHECK: %[[BYTE:.*]] = llvm.add %[[D]], %{{.*}} : i64
// CHECK: %[[BIT:.*]] = llvm.shl %[[BYTE]], %{{.*}} : i64
// CHECK: llvm.xor %[[OLD]], %[[V]]
// CHECK: schedule.state.store %[[V]], @__talos_state_unknown[%[[D]] + 32] {alignment = 1 : i64} : i8
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_unknown_v1(%[[BIT]],
// CHECK: llvm.mlir.addressof @__talos_state_unknown_summary_v1
// CHECK: llvm.mlir.constant(2 : i64)
// A writer that reported its roots itself is not instrumented again, and its
// written bits lie outside every proof.
// CHECK-NOT: talos_rt_v1_native_state_mark_unknown
// CHECK: schedule.state.store %[[V]], @__talos_state_unknown[%[[D]]] {alignment = 1 : i64} : i8
// CHECK-NEXT: schedule.state.load @__talos_state_unknown[%[[D]] + 1]
// A store without a declared range publishes at bit (%d + 1) * 8 and reports
// its bits through the runtime, which finds their roots.
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_unknown_v1(
// CHECK: %[[MBYTE:.*]] = llvm.add %[[D]], %{{.*}} : i64
// CHECK: %[[MBIT:.*]] = llvm.shl %[[MBYTE]], %{{.*}} : i64
// CHECK: llvm.call @talos_rt_v1_native_state_mark_unknown(%{{.*}}, %[[MBIT]], %{{.*}})
// CHECK: llvm.return

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", runtime.state_bits = 512 : i64} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<64xi8>) : !llvm.array<64 x i8>
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  // Root 0 covers bits [32, 48), root 1 bits [256, 320); a proof reads root 1.
  llvm.mlir.global internal @__talos_state_unknown_summary_v1(dense<3> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal constant @__talos_state_unknown_summary_roots_v1(dense<[32, 16, 0, 256, 64, 0]> : tensor<6xi64>) : !llvm.array<6 x i64>
  llvm.mlir.global internal constant @__talos_state_unknown_summary_patterns_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.func @talos_rt_v1_native_state_mark_unknown(!llvm.ptr, i64, i64)
  llvm.mlir.global internal constant @__talos_eval_proof_dependencies_v1(dense<0> : tensor<1xi64>) {schedule.eval.proof_coverage = array<i64: 256, 320>} : !llvm.array<1 x i64>
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @__talos_eval_promotion_recheck_range_v1(i64, i64)
  llvm.func @writes(%v: i8, %d: i64) {
    schedule.state.store %v, @__talos_state_unknown[%d + 32] {alignment = 1 : i64, written_bits = array<i64: 256, 64>} : i8
    schedule.state.store %v, @__talos_state_unknown[%d] {alignment = 1 : i64, summary_reported, written_bits = array<i64: 0, 8>} : i8
    schedule.state.store %v, @__talos_state_unknown[%d + 1] {alignment = 1 : i64} : i8
    llvm.return
  }
}
