// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm | FileCheck %s

// A word access of a region's ready set reads or changes its pending leaves,
// so the region materializes them before it; a word of another ready set is
// distinct storage and keeps them local (IEEE 1800-2023 4.7).
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  // CHECK-LABEL: llvm.func @own_word(
  // CHECK: schedule.ready.word.store %{{.*}}, @__talos_aot_model_ingress_v1[0]
  // CHECK-NEXT: %[[SEEN:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
  // CHECK-NOT: schedule.ready.word.store
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
}
