// RUN: talos-opt %s --canonicalize --cse | FileCheck %s

// Typed ready set and mask word loads only read their global, and their
// stores only write it. Group dataflow relies on this: region DCE erases an
// unused load, and a load is merged with an earlier one only when no write
// lies between them. A store stays without uses.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  // CHECK-LABEL: llvm.func @dead()
  // CHECK-NEXT: llvm.return
  llvm.func @dead() {
    %ready = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %mask = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[1]
    llvm.return
  }
  // CHECK-LABEL: llvm.func @duplicate()
  // CHECK-NEXT: %[[READY:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[1]
  // CHECK-NEXT: %[[MASK:.*]] = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
  // CHECK-NEXT: llvm.or %[[READY]], %[[READY]] : i64
  // CHECK-NEXT: llvm.or %[[MASK]], %[[MASK]] : i64
  llvm.func @duplicate() -> i64 {
    %a = schedule.ready.word.load @__talos_aot_model_ingress_v1[1]
    %b = schedule.ready.word.load @__talos_aot_model_ingress_v1[1]
    %c = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
    %d = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
    %ab = llvm.or %a, %b : i64
    %cd = llvm.or %c, %d : i64
    %all = llvm.or %ab, %cd : i64
    llvm.return %all : i64
  }
  // CHECK-LABEL: llvm.func @stored(
  // CHECK-SAME: %[[V:.*]]: i64)
  // CHECK-NEXT: %[[BEFORE:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: schedule.ready.word.store %[[V]], @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[AFTER:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[OLD:.*]] = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
  // CHECK-NEXT: schedule.mask.store %[[V]], @__talos_eval_promotion_pending_mask_v1[0]
  // CHECK-NEXT: %[[NEW:.*]] = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
  // CHECK-NEXT: llvm.or %[[BEFORE]], %[[AFTER]] : i64
  // CHECK-NEXT: llvm.or %[[OLD]], %[[NEW]] : i64
  llvm.func @stored(%v: i64) -> i64 {
    %a = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    schedule.ready.word.store %v, @__talos_aot_model_ingress_v1[0]
    %b = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %c = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
    schedule.mask.store %v, @__talos_eval_promotion_pending_mask_v1[0]
    %d = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0]
    %ab = llvm.or %a, %b : i64
    %cd = llvm.or %c, %d : i64
    %all = llvm.or %ab, %cd : i64
    llvm.return %all : i64
  }
  // CHECK-LABEL: llvm.func @unused_store(
  // CHECK-SAME: %[[V:.*]]: i64)
  // CHECK-NEXT: schedule.ready.word.store %[[V]], @__talos_aot_model_ingress_v1[1]
  // CHECK-NEXT: schedule.mask.store %[[V]], @__talos_eval_promotion_pending_mask_v1[1]
  // CHECK-NEXT: llvm.return
  llvm.func @unused_store(%v: i64) {
    schedule.ready.word.store %v, @__talos_aot_model_ingress_v1[1]
    schedule.mask.store %v, @__talos_eval_promotion_pending_mask_v1[1]
    llvm.return
  }
}
