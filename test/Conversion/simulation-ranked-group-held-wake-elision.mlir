// RUN: talos-opt %s --talos-materialize-native-eval-groups -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s < %t.mlir

// A held wake, which an NBA-equivalent store publishes until the NBA region's
// updates are complete (IEEE 1800-2023 4.4.2.4, 4.5, 4.6(b), 4.7), is elided
// like an ingress wake when it targets a member that still runs later in the
// sweep and reads the stored value there. The one to the member that already
// ran stays.
// TRACE: talos unconditional member publications elided: 1
// CHECK-LABEL: llvm.func @held()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK: %[[EARLIER:.*]] = llvm.mlir.constant(1 : i64) : i64
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0]
// CHECK-NOT: @__talos_eval_nba_held_wakes_v1
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[1]
// CHECK-NEXT: %[[HELD:.*]] = schedule.ready.word.load @__talos_eval_nba_held_wakes_v1[0]
// CHECK-NEXT: %[[WAKE:.*]] = llvm.or %[[HELD]], %[[EARLIER]] : i64
// CHECK-NEXT: schedule.ready.word.store %[[WAKE]], @__talos_eval_nba_held_wakes_v1[0]
// CHECK-NOT: @__talos_eval_nba_held_wakes_v1
// CHECK-LABEL: llvm.func @held.fallback()

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", native.debug_timing} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<2xi8>) : !llvm.array<2 x i8>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @slow(0 : i32) : i32
  llvm.func @held() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @held_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.unconditional_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @held} {
    %first = llvm.mlir.constant(1 : i64) : i64
    %second = llvm.mlir.constant(2 : i64) : i64
    %value = llvm.mlir.constant(7 : i8) : i8
    %a = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 64 : i64, schedule.eval.activation_entry = 0 : i32}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %first {capacity = 64 : i64, consume = true}
    schedule.state.store %value, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.ready.update @__talos_eval_nba_held_wakes_v1[0], %second {capacity = 64 : i64, consume = false}
    %b = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 64 : i64, schedule.eval.activation_entry = 1 : i32}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %second {capacity = 64 : i64, consume = true}
    schedule.state.store %value, @__talos_state_value[1] {alignment = 1 : i64} : i8
    schedule.ready.update @__talos_eval_nba_held_wakes_v1[0], %first {capacity = 64 : i64, consume = false}
    llvm.return
  }
}
