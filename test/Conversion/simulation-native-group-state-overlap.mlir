// RUN: talos-opt %s --talos-materialize-native-eval-groups | FileCheck %s

// Differently sized overlapping accesses share one physical SSA window.
// A byte read observes the preceding wide blocking store (LRM 4.9.3),
// while a separate range remains a separate slot.
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>

  llvm.func @wide() attributes {schedule.eval.infallible} {
    %v = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i16
    %one = llvm.mlir.constant(1 : i16) : i16
    %next = llvm.add %v, %one : i16
    schedule.state.store %next, @__talos_state_value[0] {alignment = 1 : i64} : i16
    %narrow = llvm.trunc %next : i16 to i8
    schedule.state.store %narrow, @__talos_state_value[4] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @overlapping() attributes {schedule.eval.infallible} {
    %v = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i16
    %hi = schedule.state.load @__talos_state_value[1] {alignment = 1 : i64} : i8
    %ext = llvm.zext %hi : i8 to i16
    %next = llvm.add %v, %ext : i16
    schedule.state.store %next, @__talos_state_value[0] {alignment = 1 : i64} : i16
    %old = schedule.state.load @__talos_state_value[4] {alignment = 1 : i64} : i8
    %result = llvm.add %old, %hi : i8
    schedule.state.store %result, @__talos_state_value[4] {alignment = 1 : i64} : i8
    llvm.return
  }
  // CHECK-LABEL: llvm.func @group()
  // CHECK-SAME: schedule.eval.ssa_value_ranges = 2 : i64
  // CHECK: schedule.state.load @__talos_state_value[0] {{.*}} : i16
  // CHECK: schedule.state.load @__talos_state_value[4] {{.*}} : i8
  // CHECK-NOT: schedule.state.load
  // CHECK: llvm.lshr {{.*}} : i16
  // CHECK: llvm.trunc {{.*}} : i16 to i8
  // CHECK-NOT: schedule.state.load
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0] {{.*}} : i16
  // CHECK-NOT: schedule.state.load
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[4] {{.*}} : i8
  // CHECK: llvm.return
  llvm.func @group() attributes {schedule.eval.ranked_members = array<i32: 0>} {
    llvm.call @wide() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @overlapping() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
}
