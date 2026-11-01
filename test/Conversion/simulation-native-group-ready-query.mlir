// RUN: talos-opt %s --talos-materialize-native-eval-groups --convert-native-schedule-actions-to-llvm | FileCheck %s

// A clocked kernel's certificate query updates only proof metadata and its own
// retry count. It activates no process and selects only a value domain (IEEE
// 1800-2023 4.3, 4.5, 6.3.1), so ready words need not be stored around it: both
// consumes and the publication between them collapse to one store, as for the
// query it wraps.
module {
  llvm.mlir.global internal @ready(1 : i64) : i64
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.mlir.global internal @retry(0 : i8) : i8
  llvm.func internal @__talos_eval_kernel_promotion_ready_v1(%owner: i64) -> i1 {
    %yes = llvm.mlir.constant(true) : i1
    llvm.return %yes : i1
  }
  llvm.func internal @__talos_eval_clocked_kernel_ready_v1(%owner: i64, %count: !llvm.ptr) -> i1 {
    %known = llvm.call @__talos_eval_kernel_promotion_ready_v1(%owner) : (i64) -> i1
    llvm.return %known : i1
  }
  llvm.func @producer() attributes {schedule.eval.infallible} {
    %base = llvm.mlir.addressof @ready : !llvm.ptr
    %two = llvm.mlir.constant(2 : i64) : i64
    schedule.ready.update %base, %two {capacity = 64 : i64, word = 0 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    llvm.return
  }
  llvm.func @consumer() attributes {schedule.eval.infallible} {
    %out = llvm.mlir.addressof @observed : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %out : i32, !llvm.ptr
    llvm.return
  }
  // CHECK-LABEL: llvm.func @group()
  // CHECK-NOT: llvm.store {{.*}}@ready
  // CHECK: llvm.call @__talos_eval_clocked_kernel_ready_v1(
  // CHECK-COUNT-2: llvm.store
  // CHECK-NOT: llvm.store
  // CHECK: llvm.return
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    %base = llvm.mlir.addressof @ready : !llvm.ptr
    %retry = llvm.mlir.addressof @retry : !llvm.ptr
    %zero = llvm.mlir.constant(0 : i64) : i64
    %one = llvm.mlir.constant(1 : i64) : i64
    %two = llvm.mlir.constant(2 : i64) : i64
    %first = schedule.ready.read %base {capacity = 64 : i64, word = 0 : i64} : (!llvm.ptr) -> i64
    %bit0 = llvm.and %first, %one : i64
    %active0 = llvm.icmp "ne" %bit0, %zero : i64
    llvm.cond_br %active0, ^first, ^next
  ^first:
    schedule.ready.update %base, %one {capacity = 64 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    %known = llvm.call @__talos_eval_clocked_kernel_ready_v1(%zero, %retry) : (i64, !llvm.ptr) -> i1
    llvm.call @producer() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.br ^next
  ^next:
    %second = schedule.ready.read %base {capacity = 64 : i64, word = 0 : i64} : (!llvm.ptr) -> i64
    %bit1 = llvm.and %second, %two : i64
    %active1 = llvm.icmp "ne" %bit1, %zero : i64
    llvm.cond_br %active1, ^second, ^done
  ^second:
    schedule.ready.update %base, %two {capacity = 64 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    llvm.call @consumer() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.br ^done
  ^done:
    llvm.return
  }
}
