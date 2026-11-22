// RUN: talos-opt %s --split-input-file --test-talos-lower-startup-lifecycle | FileCheck %s --implicit-check-not=talos_rt_v1_vpi_ --implicit-check-not=resolve_initial_drivers --implicit-check-not=native.startup --implicit-check-not=schedule.lifecycle

// Most executables only synchronize the canonical image's state into the
// native planes before the root process spawns: no driver resolution, no
// VPI startup, and no finish or shutdown in main. Eight plane bytes hold all
// 64 state bits.
// CHECK-LABEL: llvm.func @main()
// CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
// CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]] {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.mlir.addressof @__talos_state_unknown
// CHECK-NEXT: %[[VALUE:.*]] = llvm.mlir.addressof @__talos_state_value
// CHECK-NEXT: %[[BITS:.*]] = llvm.mlir.constant(64 : i64) : i64
// CHECK-NEXT: %[[SYNCED:.*]] = llvm.call @talos_rt_v1_native_state_sync(%[[CONTEXT]], %[[VALUE]], %[[UNKNOWN]], %[[BITS]])
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[SYNCED]])
// CHECK-NEXT: llvm.call @spawn_root()
// CHECK: llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}
// CHECK-NEXT: llvm.func @talos_rt_v1_native_state_sync(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i32 attributes {native.runtime_entry = #native.runtime_entry<native_state_sync>}
module attributes {native.startup_state_sync} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @spawn_root()
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 64 state_sync
    llvm.call @spawn_root() : () -> ()
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}

// -----

// A two-state executable has no unknown plane and passes a null one.
// CHECK-LABEL: llvm.func @main()
// CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
// CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
// CHECK-NEXT: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: %[[VALUE:.*]] = llvm.mlir.addressof @__talos_state_value
// CHECK-NEXT: %[[BITS:.*]] = llvm.mlir.constant(64 : i64) : i64
// CHECK-NEXT: %[[SYNCED:.*]] = llvm.call @talos_rt_v1_native_state_sync(%[[CONTEXT]], %[[VALUE]], %[[NULL]], %[[BITS]])
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[SYNCED]])
module attributes {native.startup_state_sync, runtime.execution_flags = #runtime.execution_flags<two_state>} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @main() -> i32 {
    schedule.lifecycle.start state_bits 64 state_sync
    %zero = llvm.mlir.constant(0 : i32) : i32
    llvm.return %zero : i32
  }
}
