// RUN: talos-opt %s --talos-materialize-native-eval-groups | FileCheck %s

// Group materialization forwards typed state accesses between members as it
// does LLVM ones (see simulation-native-group-state-boundary.mlir): the
// window each plane's members share is acquired once, kept in SSA, and
// published and reacquired around the opaque helper (IEEE 1800-2023 4.3,
// 4.9.3); no member reads it from memory. Inlined typed accesses carry their
// member as a property.
// CHECK-LABEL: llvm.func @group()
// CHECK-SAME: schedule.eval.ssa_unknown_ranges = 1 : i64
// CHECK-SAME: schedule.eval.ssa_value_ranges = 1 : i64
// CHECK-DAG: %[[X:.*]] = llvm.getelementptr %{{.*}}[0]
// CHECK-DAG: %[[V:.*]] = llvm.getelementptr %{{.*}}[0]
// CHECK: %[[VALUE:.*]] = llvm.load %[[V]]
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.load %[[X]]
// CHECK-NOT: schedule.state.load
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[1] {alignment = 1 : i64, owner = 1 : i32} : i8
// CHECK-NEXT: schedule.state.store %{{.*}}, @__talos_state_unknown[1] {alignment = 1 : i64, owner = 1 : i32} : i8
// CHECK-NEXT: llvm.store %{{.*}}, %[[V]]
// CHECK-NEXT: llvm.store %{{.*}}, %[[X]]
// CHECK-NEXT: llvm.call @mutate()
// CHECK-NEXT: llvm.load %[[X]]
// CHECK-NEXT: llvm.load %[[V]]
// CHECK-NOT: schedule.state.load
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[2] {alignment = 1 : i64, owner = 2 : i32} : i8
// CHECK-NEXT: schedule.state.store %{{.*}}, @__talos_state_unknown[2] {alignment = 1 : i64, owner = 2 : i32} : i8
// CHECK-NEXT: llvm.return
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  llvm.mlir.global internal @__talos_state_value(dense<[7, 0, 0]> : tensor<3xi8>) : !llvm.array<3 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<[0, 0, 0]> : tensor<3xi8>) : !llvm.array<3 x i8>
  llvm.func @writer() attributes {schedule.eval.infallible} {
    %one = llvm.mlir.constant(1 : i8) : i8
    %all = llvm.mlir.constant(-1 : i8) : i8
    %oldv = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %oldx = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %newv = llvm.add %oldv, %one : i8
    %newx = llvm.xor %oldx, %all : i8
    schedule.state.store %newv, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %newx, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @reader() attributes {schedule.eval.infallible} {
    %value = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %unknown = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    schedule.state.store %value, @__talos_state_value[1] {alignment = 1 : i64} : i8
    schedule.state.store %unknown, @__talos_state_unknown[1] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @after_mutation() attributes {schedule.eval.infallible} {
    %value = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %unknown = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    schedule.state.store %value, @__talos_state_value[2] {alignment = 1 : i64} : i8
    schedule.state.store %unknown, @__talos_state_unknown[2] {alignment = 1 : i64} : i8
    llvm.return
  }
  // An opaque boundary to group materialization.
  llvm.func @mutate() -> i1 attributes {passthrough = ["noinline"]} {
    %forty = llvm.mlir.constant(40 : i8) : i8
    %zero = llvm.mlir.constant(0 : i8) : i8
    schedule.state.store %forty, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %zero, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %ok = llvm.mlir.constant(true) : i1
    llvm.return %ok : i1
  }
  llvm.func @group() -> i1 attributes {schedule.eval.ranked_members = array<i32: 0, 1>} {
    llvm.call @writer() {schedule.eval.group_member = 0 : i32} : () -> ()
    llvm.call @reader() {schedule.eval.group_member = 1 : i32} : () -> ()
    %ok = llvm.call @mutate() : () -> i1
    llvm.call @after_mutation() {schedule.eval.group_member = 2 : i32} : () -> ()
    llvm.return %ok : i1
  }
}
