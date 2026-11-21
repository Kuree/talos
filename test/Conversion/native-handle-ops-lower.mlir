// RUN: talos-opt %s --test-talos-lower-native-handle-ops | FileCheck %s

// Once AOT planning has read a selection, an offset becomes the runtime's
// handle offset, and one proved in bounds keeps the proof as a tag that native
// finalization turns into the plain sum. A guard becomes a select of the
// invalid handle (IEEE 1800-2023 7.4.5, 11.5.1). The order of the selection is
// kept.
module {
  llvm.func @talos_rt_v1_native_handle_offset(i64, i64) -> i64

  // CHECK-LABEL: llvm.func @chain(
  // CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64, %[[VALID:.*]]: i1)
  // CHECK-NEXT: %[[ELEMENT:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[ROOT]], %[[INDEX]]) : (i64, i64) -> i64
  // CHECK-NEXT: %[[INVALID:.*]] = arith.constant -1 : i64
  // CHECK-NEXT: %[[GUARDED:.*]] = arith.select %[[VALID]], %[[ELEMENT]], %[[INVALID]] : i64
  // CHECK-NEXT: %[[FIELD:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[GUARDED]], %[[INDEX]]) {native.in_bounds_handle_offset} : (i64, i64) -> i64
  // CHECK-NEXT: llvm.return %[[FIELD]]
  llvm.func @chain(%root: i64, %index: i64, %valid: i1) -> i64 {
    %element = schedule.handle.offset %root, %index
    %guarded = schedule.handle.guard %valid, %element
    %field = schedule.handle.offset %guarded, %index in_bounds
    llvm.return %field : i64
  }

  // A frame handle's validity compares the handle with the invalid handle; its
  // select takes that same constant.
  // CHECK-LABEL: llvm.func @frame(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[AMOUNT:.*]]: i64)
  // CHECK-NEXT: %[[INVALID:.*]] = llvm.mlir.constant(-1 : i64) : i64
  // CHECK-NEXT: %[[VALID:.*]] = arith.cmpi ne, %[[HANDLE]], %[[INVALID]] : i64
  // CHECK-NEXT: %[[SUM:.*]] = arith.addi %[[HANDLE]], %[[AMOUNT]] : i64
  // CHECK-NEXT: %[[SELECTED:.*]] = arith.select %[[VALID]], %[[SUM]], %[[INVALID]] : i64
  // CHECK-NEXT: llvm.return %[[SELECTED]]
  llvm.func @frame(%handle: i64, %amount: i64) -> i64 {
    %invalid = llvm.mlir.constant(-1 : i64) : i64
    %valid = arith.cmpi ne, %handle, %invalid : i64
    %sum = arith.addi %handle, %amount : i64
    %selected = schedule.handle.guard %valid, %sum
    llvm.return %selected : i64
  }
}
