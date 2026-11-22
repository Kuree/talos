// RUN: talos-opt %s | talos-opt | FileCheck %s

// A selection offsets a stable handle and guards the result with its validity.
// CHECK-LABEL: llvm.func @select(
// CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64, %[[VALID:.*]]: i1)
llvm.func @select(%root: i64, %index: i64, %valid: i1) -> i64 {
  // CHECK: %[[ELEMENT:.*]] = schedule.handle.offset %[[ROOT]], %[[INDEX]]{{$}}
  %element = schedule.handle.offset %root, %index
  // CHECK: schedule.handle.guard %[[VALID]], %[[ELEMENT]]{{$}}
  %guarded = schedule.handle.guard %valid, %element
  llvm.return %guarded : i64
}

// An offset may carry the proof that its handle is valid and that it stays in
// bounds.
// CHECK-LABEL: llvm.func @proved(
// CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64)
llvm.func @proved(%root: i64, %index: i64) -> i64 {
  // CHECK: schedule.handle.offset %[[ROOT]], %[[INDEX]] in_bounds{{$}}
  %field = schedule.handle.offset %root, %index in_bounds
  llvm.return %field : i64
}
