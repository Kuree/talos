// RUN: talos-opt %s --talos-materialize-native-eval-groups | FileCheck %s

// A group keeps its ingress words in SSA between executor boundaries, as a
// local form of the same pending activations (IEEE 1800-2023 4.7): typed word
// accesses of a static word read and write the SSA value. An opaque call may
// observe or publish readiness, so the word is written before it and read
// again after it; a dynamic word access and the return are boundaries too.
// CHECK-LABEL: llvm.func @group(
// CHECK-SAME: schedule.eval.ssa_ready_words = 1
// CHECK: %[[INITIAL:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]{{$}}
// CHECK-NOT: activation_entry
// CHECK: %[[CONSUMED:.*]] = llvm.xor %[[INITIAL]],
// CHECK-NEXT: schedule.ready.word.store %[[CONSUMED]], @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: llvm.call @opaque()
// CHECK-NEXT: %[[ACQUIRED:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: llvm.br ^{{bb[0-9]+}}(%[[ACQUIRED]] : i64)
// CHECK: llvm.store {{.*}}schedule.eval.group_owner = 1
// CHECK: ^{{bb[0-9]+}}(%[[PENDING:[0-9]+]]: i64):
// CHECK-NEXT: schedule.ready.word.store %[[PENDING]], @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: %[[ANY:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[%{{.*}}]
// CHECK-NEXT: %[[AFTER:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: schedule.ready.word.store %[[AFTER]], @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: llvm.return %[[ANY]] : i64
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<3> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @observed(0 : i32) : i32
  llvm.func @opaque()
  llvm.func @member0() attributes {schedule.eval.infallible} {
    llvm.call @opaque() : () -> ()
    llvm.return
  }
  llvm.func @member1() attributes {schedule.eval.infallible} {
    %out = llvm.mlir.addressof @observed : !llvm.ptr
    %one = llvm.mlir.constant(1 : i32) : i32
    llvm.store %one, %out : i32, !llvm.ptr
    llvm.return
  }
  llvm.func @group(%word: i64) -> i64 attributes {schedule.eval.ranked_members = array<i32: 0, 1>, schedule.eval.group_ingress = @__talos_aot_model_ingress_v1} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %one = llvm.mlir.constant(1 : i64) : i64
    %two = llvm.mlir.constant(2 : i64) : i64
    %first = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    %bit0 = llvm.and %first, %one : i64
    %active0 = llvm.icmp "ne" %bit0, %zero : i64
    llvm.cond_br %active0, ^run0, ^check1
  ^run0:
    %rest0 = llvm.xor %first, %one : i64
    schedule.ready.word.store %rest0, @__talos_aot_model_ingress_v1[0]
    llvm.call @member0() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.br ^check1
  ^check1:
    %second = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
    %bit1 = llvm.and %second, %two : i64
    %active1 = llvm.icmp "ne" %bit1, %zero : i64
    llvm.cond_br %active1, ^run1, ^done
  ^run1:
    %rest1 = llvm.xor %second, %two : i64
    schedule.ready.word.store %rest1, @__talos_aot_model_ingress_v1[0]
    llvm.call @member1() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.br ^done
  ^done:
    %any = schedule.ready.word.load @__talos_aot_model_ingress_v1[%word]
    llvm.return %any : i64
  }
}
