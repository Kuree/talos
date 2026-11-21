// RUN: talos-opt %s --talos-materialize-native-eval-groups -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s < %t.mlir
// RUN: talos-opt %s --mlir-disable-threading --talos-materialize-native-eval-groups | diff %t.mlir -

// A topological order of SCCs still contains backward edges inside an SCC.
// The first member reads valid before the second member changes it. The
// second member must republish the first, which has already run (IEEE
// 1800-2023 4.3-4.5, 4.9.1, 10.3.2). Running both members unconditionally
// does not make that backward publication redundant. Only the forward
// publication to the member that still runs later may disappear.
// TRACE: talos unconditional member publications elided: 1
// CHECK-LABEL: llvm.func @feedback()
// CHECK-SAME: schedule.eval.control_flow_dataflow
// CHECK: %[[CHANGED:.*]] = llvm.icmp "ne"
// CHECK: %[[BACKWARD:.*]] = llvm.select %[[CHANGED]]
// CHECK: %[[PUBLISHED:.*]] = llvm.or %{{.*}}, %[[BACKWARD]]
// CHECK: %[[READY:.*]] = llvm.or %{{.*}}, %[[PUBLISHED]]
// CHECK-NEXT: schedule.ready.word.store %[[READY]], @__talos_aot_model_ingress_v1[0]
// CHECK-LABEL: llvm.func @feedback.fallback()

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", native.debug_timing} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<2xi8>) : !llvm.array<2 x i8>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<2> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @slow(0 : i32) : i32

  llvm.func @feedback() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @feedback_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.unconditional_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1, schedule.eval.dataflow_candidate = @feedback} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %first = llvm.mlir.constant(1 : i64) : i64
    %second = llvm.mlir.constant(2 : i64) : i64
    %value = llvm.mlir.constant(7 : i8) : i8

    %a = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 64 : i64, schedule.eval.activation_entry = 0 : i32}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %first {capacity = 64 : i64, consume = true}
    %old = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %old, @__talos_state_value[1] {alignment = 1 : i64} : i8
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %second {capacity = 64 : i64, consume = false}

    %b = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 64 : i64, schedule.eval.activation_entry = 1 : i32}
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %second {capacity = 64 : i64, consume = true}
    %before = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %changed = llvm.icmp "ne" %before, %value : i8
    schedule.state.store %value, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %backward = llvm.select %changed, %first, %zero : i1, i64
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %backward {capacity = 64 : i64, consume = false}
    llvm.return
  }

  // The caller must see pending work after the first sweep, then the second
  // sweep must settle the output and clear that work without another event.
  llvm.func @main() -> i32 {
    %slow = llvm.mlir.addressof @slow : !llvm.ptr
    %zero = llvm.mlir.constant(0 : i64) : i64
    %first = llvm.mlir.constant(1 : i64) : i64
    %value = llvm.mlir.constant(7 : i8) : i8
    %zero32 = llvm.mlir.constant(0 : i32) : i32
    %failure = llvm.mlir.constant(1 : i32) : i32
    llvm.call @feedback() : () -> ()
    %pending = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %again = llvm.icmp "eq" %pending, %first : i64
    llvm.call @feedback() : () -> ()
    %done = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %quiet = llvm.icmp "eq" %done, %zero : i64
    %result = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i8
    %correct = llvm.icmp "eq" %result, %value : i8
    %fallback = llvm.load %slow : !llvm.ptr -> i32
    %native = llvm.icmp "eq" %fallback, %zero32 : i32
    %a = llvm.and %again, %quiet : i1
    %b = llvm.and %correct, %native : i1
    %ok = llvm.and %a, %b : i1
    %status = llvm.select %ok, %zero32, %failure : i1, i32
    llvm.return %status : i32
  }
}
