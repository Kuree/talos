// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm | FileCheck %s

// A word access of a region's ready set reads or changes its pending leaves,
// so the region materializes them before it, as before any point where an
// event may be selected from the set (IEEE 1800-2023 4.5). A word of another
// ready set or of an eval mask is distinct storage and keeps them local: no
// observer sees the set in between, so the user-visible effect is unchanged
// (4.3, 4.7).
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  // CHECK-LABEL: llvm.func @own_word(
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[SEEN:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: llvm.return %[[SEEN]]
  llvm.func @own_word() -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %seen = schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = false}
      %word = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = true}
      schedule.ready.yield %word : i64
    } : i64
    llvm.return %seen : i64
  }
  // CHECK-LABEL: llvm.func @other_word(
  // CHECK-NOT: @__talos_aot_model_ingress_v1
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_eval_nba_held_wakes_v1[0]
  // CHECK: schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: llvm.return
  llvm.func @other_word(%bits: i64) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = false}
      schedule.ready.word.store %bits, @__talos_eval_nba_held_wakes_v1[0]
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
      schedule.ready.yield
    }
    llvm.return
  }
  // An eval mask is distinct storage as well, whether a typed access or a raw
  // address names it.
  // CHECK-LABEL: llvm.func @mask_word(
  // CHECK-NOT: @__talos_aot_model_ingress_v1
  // CHECK: schedule.mask.store %{{.*}}, @__talos_eval_promotion_pending_mask_v1[0]
  // CHECK-NOT: @__talos_aot_model_ingress_v1
  // CHECK: schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: llvm.return
  llvm.func @mask_word(%bits: i64) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = false}
      schedule.mask.store %bits, @__talos_eval_promotion_pending_mask_v1[0]
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
      schedule.ready.yield
    }
    llvm.return
  }
  // CHECK-LABEL: llvm.func @raw_mask(
  // CHECK: %[[MASK:.*]] = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1
  // CHECK-NOT: @__talos_aot_model_ingress_v1
  // CHECK: llvm.store %{{.*}}, %[[MASK]] : i64, !llvm.ptr
  // CHECK-NOT: @__talos_aot_model_ingress_v1
  // CHECK: schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: llvm.return
  llvm.func @raw_mask(%bits: i64) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %mask = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = false}
      llvm.store %bits, %mask : i64, !llvm.ptr
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
      schedule.ready.yield
    }
    llvm.return
  }
}
