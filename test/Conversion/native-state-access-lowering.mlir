// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))' | FileCheck %s --implicit-check-not=schedule.state

// Typed state accesses become the LLVM accesses they stand for: the plane's
// address, byte GEPs to the window, and a load or store of the same
// alignment, and a window address is the window's byte GEPs. Their
// properties served native passes before this point; LLVM needs none of them,
// while other dialects' annotations stay. A plane's address and a window's
// address are each taken once per block, at their first use; an address
// nothing uses is not taken.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)
  // CHECK-LABEL: llvm.func @access(
  // CHECK-SAME: %[[V:.*]]: i64, %[[DYN:.*]]: i64, %[[C:.*]]: i1)
  // CHECK-NEXT: %[[VBASE:.*]] = llvm.mlir.addressof @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[UBASE:.*]] = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
  // CHECK-NEXT: %[[UADDR:.*]] = llvm.getelementptr %[[UBASE]][4] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: %[[X:.*]] = llvm.load %[[UADDR]] {alignment = 1 : i64, test.tag} : !llvm.ptr -> i8
  // CHECK-NEXT: %[[VADDR:.*]] = llvm.getelementptr %[[VBASE]][%[[DYN]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %[[V]], %[[VADDR]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK-NEXT: %[[WADDR:.*]] = llvm.getelementptr %[[VADDR]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[WADDR]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // The same window in the same block shares its address, accessed or taken.
  // CHECK-NEXT: llvm.store %[[V]], %[[WADDR]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK-NEXT: llvm.call @use(%[[WADDR]])
  // An offset past the GEP's constant range is an i64 index.
  // CHECK-NEXT: %[[FAR:.*]] = llvm.mlir.constant(300000000 : i64) : i64
  // CHECK-NEXT: %[[FADDR:.*]] = llvm.getelementptr %[[VBASE]][%[[FAR]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[FADDR]] {alignment = 1 : i64} : !llvm.ptr -> i8
  // Offset zero is the plane's address.
  // CHECK-NEXT: llvm.load %[[VBASE]] {alignment = 1 : i64} : !llvm.ptr -> i8
  // CHECK-NEXT: llvm.call @use(%[[VBASE]])
  // Another block takes its own addresses.
  // CHECK: ^bb1:
  // CHECK-NEXT: %[[UBASE2:.*]] = llvm.mlir.addressof @__talos_state_unknown : !llvm.ptr
  // CHECK-NEXT: %[[UADDR2:.*]] = llvm.getelementptr %[[UBASE2]][4] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %{{.*}}, %[[UADDR2]] {alignment = 1 : i64} : i8, !llvm.ptr
  llvm.func @access(%v: i64, %dyn: i64, %c: i1) -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    %x = schedule.state.load @__talos_state_unknown[4] {alignment = 1 : i64, owner = 3 : i32, test.tag} : i8
    schedule.state.store %v, @__talos_state_value[%dyn] {alignment = 8 : i64, window = array<i64: 0, 16>, written_bits = array<i64: 0, 64>, latch_destination} : i64
    %w = schedule.state.load @__talos_state_value[%dyn + 8] {alignment = 8 : i64} : i64
    schedule.state.store %v, @__talos_state_value[%dyn + 8] {alignment = 8 : i64} : i64
    %window = schedule.state.window_address @__talos_state_value[%dyn + 8] : !llvm.ptr
    llvm.call @use(%window) : (!llvm.ptr) -> ()
    %unused = schedule.state.window_address @__talos_state_unknown[%dyn] : !llvm.ptr
    %f = schedule.state.load @__talos_state_value[300000000] {alignment = 1 : i64} : i8
    %z = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    %s = llvm.add %x, %f : i8
    %t = llvm.add %s, %z : i8
    llvm.cond_br %c, ^bb1, ^bb2
  ^bb1:
    schedule.state.store %t, @__talos_state_unknown[4] {alignment = 1 : i64} : i8
    llvm.br ^bb2
  ^bb2:
    llvm.return %t : i8
  }

  // A contribution plane is reached through the pointer its global binds,
  // taken once per block like a plane's address.
  // CHECK-LABEL: llvm.func @contribution(
  // CHECK-SAME: %[[MASK:.*]]: i8, %[[D:.*]]: i64)
  // CHECK-NEXT: %[[BINDING:.*]] = llvm.mlir.addressof @__talos_continuous_mask : !llvm.ptr
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.load %[[BINDING]] {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
  // CHECK-NEXT: %[[AT:.*]] = llvm.getelementptr %[[PLANE]][3] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %[[MASK]], %[[AT]] {alignment = 1 : i64} : i8, !llvm.ptr
  // CHECK-NEXT: %[[WINDOW:.*]] = llvm.getelementptr %[[PLANE]][%[[D]]] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.call @use(%[[WINDOW]])
  // The runtime binds the plane through its global's address.
  // CHECK-NEXT: %[[BIND:.*]] = llvm.mlir.addressof @__talos_continuous_mask : !llvm.ptr
  // CHECK-NEXT: llvm.call @use(%[[BIND]])
  llvm.mlir.global external @__talos_continuous_mask() : !llvm.ptr
  llvm.func @contribution(%mask: i8, %d: i64) {
    schedule.state.store %mask, @__talos_continuous_mask[3] {alignment = 1 : i64} : i8
    %w = schedule.state.window_address @__talos_continuous_mask[%d] : !llvm.ptr
    llvm.call @use(%w) : (!llvm.ptr) -> ()
    %bind = llvm.mlir.addressof @__talos_continuous_mask : !llvm.ptr
    llvm.call @use(%bind) : (!llvm.ptr) -> ()
    llvm.return
  }
}
