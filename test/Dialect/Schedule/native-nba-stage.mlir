// RUN: talos-opt %s | talos-opt | FileCheck %s

// A static NBA site stages its RHS planes for its destination; a value without
// X/Z bits has no unknown plane.
module {
  // CHECK-LABEL: llvm.func @stage(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: !llvm.ptr, %[[UNKNOWN:.*]]: !llvm.ptr)
  llvm.func @stage(%context: !llvm.ptr, %handle: i64, %value: !llvm.ptr, %unknown: !llvm.ptr) {
    // CHECK: schedule.nba.stage %[[CONTEXT]], %[[HANDLE]], %[[VALUE]], %[[UNKNOWN]] {site = 17 : i64, state_bits = 4096 : i64, width = 72 : i64}
    schedule.nba.stage %context, %handle, %value, %unknown {site = 17 : i64, state_bits = 4096 : i64, width = 72 : i64}
    // CHECK: schedule.nba.stage %[[CONTEXT]], %[[HANDLE]], %[[VALUE]] {site = 18 : i64, state_bits = 4096 : i64, width = 8 : i64}
    schedule.nba.stage %context, %handle, %value {site = 18 : i64, state_bits = 4096 : i64, width = 8 : i64}
    llvm.return
  }
}
