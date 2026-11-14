// RUN: talos-opt %s --talos-materialize-native-eval-groups | FileCheck %s

// IEEE 1800-2023 4.3, 4.6(a), 4.9.3: forward current blocking values
// through address arithmetic and explicit proof notifications. An unrelated
// byte copy is not an observation cut for this lane. An opaque observer must
// see the latest value, and its mutation must be acquired before continuing.
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @source(42 : i8) : i8
  llvm.mlir.global internal @proof(0 : i64) : i64
  llvm.func @observer()
  llvm.func @notify(%offset: i64) attributes {schedule.eval.state_metadata_only} {
    %proof = llvm.mlir.addressof @proof : !llvm.ptr
    llvm.store %offset, %proof : i64, !llvm.ptr
    llvm.return
  }
  llvm.func @activation() attributes {schedule.eval.raw_captures} {
    %base = schedule.state.address @__talos_state_value : !llvm.ptr
    %one = llvm.mlir.constant(1 : i8) : i8
    %old = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %next = llvm.add %old, %one : i8
    schedule.state.store %next, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %address = llvm.ptrtoint %base : !llvm.ptr to i64
    %offset = llvm.sub %address, %address : i64
    llvm.call @notify(%offset) : (i64) -> ()
    %current = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %twice = llvm.add %current, %one : i8
    schedule.state.store %twice, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %other = schedule.state.window_address @__talos_state_value[4] : !llvm.ptr
    %source = llvm.mlir.addressof @source : !llvm.ptr
    %length = llvm.mlir.constant(1 : i64) : i64
    "llvm.intr.memcpy"(%other, %source, %length) {isVolatile = false} : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.call @observer() : () -> ()
    %observed = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %final = llvm.add %observed, %one : i8
    schedule.state.store %final, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
  llvm.func @read_state(%index: i64) -> i8 {
    %value = schedule.state.load @__talos_state_value[%index] {alignment = 1 : i64} : i8
    llvm.return %value : i8
  }
  llvm.func @write_state(%value: i8) {
    schedule.state.store %value, @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.return
  }
}

// CHECK-LABEL: llvm.func @activation()
// CHECK-SAME: schedule.eval.ssa_value_ranges = 1 : i64
// CHECK: %[[OLD:.*]] = schedule.state.load @__talos_state_value[0]
// CHECK: %[[NEXT:.*]] = llvm.add %[[OLD]],
// CHECK-NOT: schedule.state.store
// CHECK: llvm.call @notify
// CHECK-NOT: schedule.state.load
// CHECK-NOT: schedule.state.store
// CHECK: %[[TWICE:.*]] = llvm.add %[[NEXT]],
// CHECK-NOT: schedule.state.store
// CHECK: "llvm.intr.memcpy"
// CHECK: schedule.state.store %[[TWICE]], @__talos_state_value[0]
// CHECK-NEXT: llvm.call @observer
// CHECK-NEXT: %[[ACQUIRED:.*]] = schedule.state.load @__talos_state_value[0]
// CHECK: %[[FINAL:.*]] = llvm.add %[[ACQUIRED]],
// CHECK: schedule.state.store %[[FINAL]], @__talos_state_value[0]
// CHECK-NEXT: llvm.return
