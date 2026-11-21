// RUN: talos-opt %s --test-talos-lower-native-state-handle-accesses | FileCheck %s

// Once AOT planning has read the eval bodies' accesses, each access of the
// state a stable handle names becomes the call of its runtime entry, on its
// plane's address and the current context, the call's status unused. A bit a
// read's handle does not name reads as X, 0 in the value plane and 1 in the
// unknown plane (IEEE 1800-2023 7.4.5, 11.5.1). A continuous store calls the
// entry that keeps the contribution for a release (10.6.2).
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global external @__talos_current_context() : !llvm.ptr
  llvm.func @talos_rt_v1_native_state_load_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, i32, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_native_state_store_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_native_state_store_continuous_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, !llvm.ptr, !llvm.ptr) -> i32

  // CHECK-LABEL: llvm.func @load(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]] {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(7 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: %[[FALLBACK:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_load_plane(%{{.*}}, %[[BASE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[PLANE]], %[[FALLBACK]], %[[BUFFER]])
  // CHECK-NEXT: llvm.return
  llvm.func @load(%handle: i64, %buffer: !llvm.ptr) {
    schedule.state.load_handle @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 7 : i64}
    schedule.state.load_handle @__talos_state_unknown[%handle] into %buffer {state_bits = 128 : i64, width = 7 : i64}
    llvm.return
  }

  // CHECK-LABEL: llvm.func @store(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr, %[[CHANGED:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_unknown
  // CHECK-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
  // CHECK-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(200 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = llvm.mlir.constant(1 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_plane(%[[CONTEXT]], %[[BASE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[PLANE]], %[[BUFFER]], %[[CHANGED]])
  // CHECK-NEXT: %[[BASE:.*]] = schedule.state.address @__talos_state_value
  // CHECK: %[[PLANE:.*]] = llvm.mlir.constant(0 : i32) : i32
  // CHECK-NEXT: llvm.call @talos_rt_v1_native_state_store_continuous_plane(%{{.*}}, %[[BASE]], %{{.*}}, %[[HANDLE]], %{{.*}}, %[[PLANE]], %[[BUFFER]], %[[CHANGED]])
  // CHECK-NEXT: llvm.return
  llvm.func @store(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    schedule.state.store_handle %buffer, @__talos_state_unknown[%handle] changed %changed {state_bits = 128 : i64, width = 200 : i64}
    schedule.state.store_handle %buffer, @__talos_state_value[%handle] changed %changed continuous {state_bits = 128 : i64, width = 200 : i64}
    llvm.return
  }
}
