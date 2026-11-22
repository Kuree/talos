// RUN: talos-opt %s --test-talos-lower-native-nba-stages | FileCheck %s --implicit-check-not=schedule.nba.stage

// A static NBA stage the eval plan did not rewrite becomes the call of the
// runtime's static NBA entry on the context, the site, the state planes'
// addresses and size, the destination handle, the width and the RHS planes.
// The RHS and the destination were evaluated when the assignment executed;
// the runtime applies the update in the NBA region (IEEE 1800-2023 4.9.4,
// 10.4.2). It reads the unknown planes only for a value with X/Z bits, so a
// value without them passes null for both. A failed stage latches its status.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @talos_rt_v1_scheduler_static_nba(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr, !llvm.ptr) -> i32
  llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i32)

  // CHECK-LABEL: llvm.func @known(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[NO_PLANE:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: %[[NO_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: %[[SITE:.*]] = llvm.mlir.constant(3 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = schedule.state.address @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(8 : i64) : i64
  // CHECK-NEXT: %[[STATUS:.*]] = llvm.call @talos_rt_v1_scheduler_static_nba(%[[CONTEXT]], %[[SITE]], %[[PLANE]], %[[NO_PLANE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[VALUE]], %[[NO_UNKNOWN]])
  // CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[STATUS]])
  // CHECK-NEXT: llvm.return
  llvm.func @known(%context: !llvm.ptr, %handle: i64, %value: !llvm.ptr) {
    schedule.nba.stage %context, %handle, %value {site = 3 : i64, state_bits = 128 : i64, width = 8 : i64}
    llvm.return
  }

  // CHECK-LABEL: llvm.func @unknown(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: !llvm.ptr, %[[UNKNOWN:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[UNKNOWN_PLANE:.*]] = schedule.state.address @__talos_state_unknown : !llvm.ptr
  // CHECK-NEXT: %[[SITE:.*]] = llvm.mlir.constant(17 : i64) : i64
  // CHECK-NEXT: %[[PLANE:.*]] = schedule.state.address @__talos_state_value : !llvm.ptr
  // CHECK-NEXT: %[[STATE:.*]] = llvm.mlir.constant(128 : i64) : i64
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // CHECK-NEXT: %[[STATUS:.*]] = llvm.call @talos_rt_v1_scheduler_static_nba(%[[CONTEXT]], %[[SITE]], %[[PLANE]], %[[UNKNOWN_PLANE]], %[[STATE]], %[[HANDLE]], %[[WIDTH]], %[[VALUE]], %[[UNKNOWN]])
  // CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[STATUS]])
  // CHECK-NEXT: llvm.return
  llvm.func @unknown(%context: !llvm.ptr, %handle: i64, %value: !llvm.ptr, %unknown: !llvm.ptr) {
    schedule.nba.stage %context, %handle, %value, %unknown {site = 17 : i64, state_bits = 128 : i64, width = 72 : i64}
    llvm.return
  }
}
