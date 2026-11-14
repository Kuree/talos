// RUN: talos-opt %s --split-input-file --talos-materialize-native-eval-groups | FileCheck %s

// Group promotion erases the accesses it forwards in SSA. Here the group's
// first operation, after inlining, is such an access, and both windows' accesses
// span blocks, so each is acquired at the function entry after its local slot,
// not at an erased access. Both are forwarded through the branch and
// published at the return (IEEE 1800-2023 4.9.3).
// CHECK-LABEL: llvm.func @group(
// CHECK-SAME: schedule.eval.ssa_value_ranges = 2 : i64
// CHECK-DAG: schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
// CHECK-DAG: schedule.state.load @__talos_state_value[4] {alignment = 1 : i64} : i8
// CHECK: llvm.cond_br
// CHECK-NOT: schedule.state
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0]
// CHECK-NEXT: schedule.state.store %{{.*}}, @__talos_state_value[4]
// CHECK-NEXT: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @low() attributes {schedule.eval.infallible} {
    %low = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %high = schedule.state.load @__talos_state_value[4] {alignment = 1 : i64} : i8
    %next = llvm.add %low, %high : i8
    schedule.state.store %next, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @high(%c: i1) attributes {schedule.eval.infallible} {
    %high = schedule.state.load @__talos_state_value[4] {alignment = 1 : i64} : i8
    llvm.cond_br %c, ^bump, ^done
  ^bump:
    %low = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %bumped = llvm.add %high, %low : i8
    schedule.state.store %bumped, @__talos_state_value[4] {alignment = 1 : i64} : i8
    llvm.br ^done
  ^done:
    llvm.return
  }
  llvm.func @group(%c: i1) attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @low() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @high(%c) {schedule.eval.group_member = 1 : i32} : (i1) -> ()
    llvm.return
  }
}

// -----

// A retained continuous contribution is memory apart from the canonical
// planes (IEEE 1800-2023 10.6.2 keeps it for a release): writing it is no
// boundary for the canonical window the members share, which stays in SSA
// from its one acquisition to the return.
// CHECK-LABEL: llvm.func @contribution_group(
// CHECK-SAME: schedule.eval.ssa_value_ranges = 1 : i64
// CHECK: schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
// CHECK-NOT: schedule.state.load
// CHECK: schedule.state.store %{{.*}}, @__talos_continuous_mask[0]
// CHECK-NOT: schedule.state
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0] {alignment = 1 : i64} : i8
// CHECK-NEXT: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global external @__talos_continuous_mask() : !llvm.ptr
  llvm.func @bump() attributes {schedule.eval.infallible} {
    %v = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %next = llvm.add %v, %one : i8
    schedule.state.store %next, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @drive() attributes {schedule.eval.infallible} {
    %v = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %all = llvm.mlir.constant(-1 : i8) : i8
    schedule.state.store %all, @__talos_continuous_mask[0] {alignment = 1 : i64} : i8
    %twice = llvm.add %v, %v : i8
    schedule.state.store %twice, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @contribution_group() attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @bump() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @drive() {schedule.eval.group_member = 1 : i32} : () -> ()
    llvm.return
  }
}
