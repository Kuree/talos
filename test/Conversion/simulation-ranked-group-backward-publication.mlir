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
// CHECK-SAME: schedule.eval.predicated_dataflow
// CHECK: llvm.icmp "ne"
// CHECK: llvm.select
// CHECK-LABEL: llvm.func @feedback.fallback()

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", native.debug_timing} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<2xi8>) : !llvm.array<2 x i8>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @ready(dense<2> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @slow(0 : i32) : i32

  llvm.func @feedback() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready} {
    %p = llvm.mlir.addressof @slow : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %p : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @feedback_candidate() attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.unconditional_members = array<i32: 0, 1>, schedule.eval.group_ingress = @ready, schedule.eval.dataflow_candidate = @feedback} {
    %ready = llvm.mlir.addressof @ready : !llvm.ptr
    %state = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %output = llvm.getelementptr %state[1] : (!llvm.ptr) -> !llvm.ptr, i8
    %zero = llvm.mlir.constant(0 : i64) : i64
    %first = llvm.mlir.constant(1 : i64) : i64
    %second = llvm.mlir.constant(2 : i64) : i64
    %value = llvm.mlir.constant(7 : i8) : i8

    %a = schedule.ready.read %ready {capacity = 64 : i64, word = 0 : i64, schedule.eval.activation_entry = 0 : i32} : (!llvm.ptr) -> i64
    schedule.ready.update %ready, %first {capacity = 64 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    %old = llvm.load %state : !llvm.ptr -> i8
    llvm.store %old, %output : i8, !llvm.ptr
    schedule.ready.update %ready, %second {capacity = 64 : i64, word = 0 : i64, consume = false} : (!llvm.ptr, i64) -> ()

    %b = schedule.ready.read %ready {capacity = 64 : i64, word = 0 : i64, schedule.eval.activation_entry = 1 : i32} : (!llvm.ptr) -> i64
    schedule.ready.update %ready, %second {capacity = 64 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    %before = llvm.load %state : !llvm.ptr -> i8
    %changed = llvm.icmp "ne" %before, %value : i8
    llvm.store %value, %state : i8, !llvm.ptr
    %backward = llvm.select %changed, %first, %zero : i1, i64
    schedule.ready.update %ready, %backward {capacity = 64 : i64, word = 0 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    llvm.return
  }

  // The caller must see pending work after the first sweep, then the second
  // sweep must settle the output and clear that work without another event.
  llvm.func @main() -> i32 {
    %ready = llvm.mlir.addressof @ready : !llvm.ptr
    %state = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
    %output = llvm.getelementptr %state[1] : (!llvm.ptr) -> !llvm.ptr, i8
    %slow = llvm.mlir.addressof @slow : !llvm.ptr
    %zero = llvm.mlir.constant(0 : i64) : i64
    %first = llvm.mlir.constant(1 : i64) : i64
    %value = llvm.mlir.constant(7 : i8) : i8
    %zero32 = llvm.mlir.constant(0 : i32) : i32
    %failure = llvm.mlir.constant(1 : i32) : i32
    llvm.call @feedback() : () -> ()
    %pending = llvm.load %ready : !llvm.ptr -> i64
    %again = llvm.icmp "eq" %pending, %first : i64
    llvm.call @feedback() : () -> ()
    %done = llvm.load %ready : !llvm.ptr -> i64
    %quiet = llvm.icmp "eq" %done, %zero : i64
    %result = llvm.load %output : !llvm.ptr -> i8
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
