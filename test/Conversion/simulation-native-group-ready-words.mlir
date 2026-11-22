// RUN: talos-opt %s --talos-materialize-native-eval-groups | FileCheck %s --implicit-check-not=llvm.alloca

// A group reads and consumes its ingress words where its members do, in the
// ready set itself: each member removes its event from the set before it
// evaluates its process (IEEE 1800-2023 4.5), and an opaque call sees the set
// as the reference algorithm leaves it (4.3, 4.7). Every typed word access
// stays at its place, with its activation entry, and the group neither copies
// a word into a local nor writes it back around an opaque call or at the
// return. A member expanded in place keeps its own accesses.
// CHECK-LABEL: llvm.func @group(
// CHECK: %[[FIRST:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
// CHECK: %[[CONSUMED:.*]] = llvm.xor %[[FIRST]],
// CHECK-NEXT: schedule.ready.word.store %[[CONSUMED]], @__talos_aot_model_ingress_v1[0]
// CHECK-NEXT: llvm.call @opaque() {schedule.eval.group_member = 0 : i32}
// CHECK-NEXT: llvm.br ^[[CHECK1:bb[0-9]+]]
// CHECK: ^[[CHECK1]]:
// CHECK-NEXT: %[[SECOND:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 1 : i32}
// CHECK: %[[REST:.*]] = llvm.xor %[[SECOND]],
// CHECK-NEXT: schedule.ready.word.store %[[REST]], @__talos_aot_model_ingress_v1[0]
// CHECK: llvm.store {{.*}}schedule.eval.group_owner = 1
// CHECK: %[[ANY:.*]] = schedule.ready.word.load @__talos_aot_model_ingress_v1[%{{.*}}]
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
