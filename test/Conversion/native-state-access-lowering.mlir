// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))' | FileCheck %s --implicit-check-not=schedule.state

// Typed state accesses become the LLVM accesses they stand for: the plane's
// address, byte GEPs to the window, and a load or store of the same
// alignment, with the access's native tags.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)
  // CHECK-LABEL: llvm.func @access(
  // CHECK-SAME: %[[V:.*]]: i64, %[[DYN:.*]]: i64)
  // CHECK: llvm.mlir.addressof @__talos_state_value {schedule.eval.group_owner = 1 : i32} : !llvm.ptr
  // CHECK: %[[UBASE:.*]] = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
  // CHECK-NEXT: %[[UADDR:.*]] = llvm.getelementptr %[[UBASE]][4] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: %[[X:.*]] = llvm.load %[[UADDR]] {alignment = 1 : i64, schedule.eval.group_owner = 3 : i32} : !llvm.ptr -> i8
  // CHECK: %[[VBASE:.*]] = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[VADDR:.*]] = llvm.getelementptr %[[VBASE]][%[[DYN]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %[[V]], %[[VADDR]] {alignment = 8 : i64, schedule.eval.unknown_write_range = array<i64: 0, 64>} : i64, !llvm.ptr
  // CHECK: %[[WBASE:.*]] = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[WDYN:.*]] = llvm.getelementptr %[[WBASE]][%[[DYN]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: %[[WADDR:.*]] = llvm.getelementptr %[[WDYN]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[WADDR]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // An offset past the GEP's constant range is an i64 index.
  // CHECK: %[[FBASE:.*]] = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[FAR:.*]] = llvm.mlir.constant(300000000 : i64) : i64
  // CHECK-NEXT: %[[FADDR:.*]] = llvm.getelementptr %[[FBASE]][%[[FAR]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[FADDR]] {alignment = 1 : i64} : !llvm.ptr -> i8
  llvm.func @access(%v: i64, %dyn: i64) -> i8 {
    %a = schedule.state.address @__talos_state_value {schedule.eval.group_owner = 1 : i32} : !llvm.ptr
    %x = schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64, schedule.eval.group_owner = 3 : i32} : i8
    schedule.state.store %v, @__talos_state_value[%dyn] {alignment = 8 : i64, schedule.eval.unknown_write_range = array<i64: 0, 64>} : i64
    %w = schedule.state.load @__talos_state_value[%dyn + 8] {alignment = 8 : i64} : i64
    %f = schedule.state.load @__talos_state_value[300000000] {alignment = 1 : i64} : i8
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    %s = llvm.add %x, %f : i8
    llvm.return %s : i8
  }
}
