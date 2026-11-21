// RUN: talos-opt %s --pass-pipeline='builtin.module(convert-native-schedule-actions-to-llvm,llvm.func(lower-native-ready-words))' | FileCheck %s
// A generated promotion query reads canonical X/Z state and proof caches and
// activates nothing (IEEE 1800-2023 4.5, 6.3.1), so pending ready words stay
// local across it: the consume and the publication commit once, after it. An
// ordinary call can observe the ready set and still materializes them first.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1() : !llvm.array<66 x i64> {
    %zero = llvm.mlir.zero : !llvm.array<66 x i64>
    llvm.return %zero : !llvm.array<66 x i64>
  }
  llvm.func @__talos_eval_kernel_promotion_ready_v1(i64) -> i1
  llvm.func @__talos_eval_group_promotion_ready_v1(i64) -> i1
  llvm.func @observe()

  // CHECK-LABEL: llvm.func @query
  // CHECK-NOT: llvm.store
  // CHECK: llvm.call @__talos_eval_kernel_promotion_ready_v1
  // CHECK-NOT: llvm.store
  // CHECK: llvm.call @__talos_eval_group_promotion_ready_v1
  // CHECK: llvm.store
  // CHECK: llvm.return
  llvm.func @query() -> i1 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %owner = arith.constant 7 : i64
    %known = schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = true}
      %member = llvm.call @__talos_eval_kernel_promotion_ready_v1(%owner) : (i64) -> i1
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 4096 : i64, consume = false}
      %group = llvm.call @__talos_eval_group_promotion_ready_v1(%owner) : (i64) -> i1
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = false}
      %both = arith.andi %member, %group : i1
      schedule.ready.yield %both : i1
    } : i1
    llvm.return %known : i1
  }

  // CHECK-LABEL: llvm.func @opaque
  // CHECK: llvm.store
  // CHECK: llvm.call @observe
  // CHECK: llvm.store
  // CHECK: llvm.return
  llvm.func @opaque() {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = true}
      llvm.call @observe() : () -> ()
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 4096 : i64, consume = false}
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = false}
      schedule.ready.yield
    }
    llvm.return
  }
}
