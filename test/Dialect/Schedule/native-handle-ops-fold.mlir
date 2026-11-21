// RUN: talos-opt %s --canonicalize | FileCheck %s

// A handle offset does not fold, like the runtime call it stands for, even
// with constant operands: producers offset constants when they create it. It
// is pure (an invalid selection is its invalid-handle result, IEEE 1800-2023
// 7.4.5, 11.5.1), so an unused one goes away.
// CHECK-LABEL: func.func @offsets
// CHECK-DAG: %[[ROOT:.*]] = arith.constant 4611686031312289797 : i64
// CHECK-DAG: %[[FOUR:.*]] = arith.constant 4 : i64
// CHECK-DAG: %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK: %[[CONSTANT:.*]] = schedule.handle.offset %[[ROOT]], %[[FOUR]]
// CHECK: %[[SAME:.*]] = schedule.handle.offset %{{.*}}, %[[ZERO]]
// CHECK-NOT: schedule.handle.offset
// CHECK: return %[[CONSTANT]], %[[SAME]] :
func.func @offsets(%handle: i64, %amount: i64) -> (i64, i64) {
  // Static object 3 at offset 5.
  %root = arith.constant 4611686031312289797 : i64
  %four = arith.constant 4 : i64
  %zero = arith.constant 0 : i64
  %constant = schedule.handle.offset %root, %four
  %same = schedule.handle.offset %handle, %zero
  %unused = schedule.handle.offset %handle, %amount
  return %constant, %same : i64, i64
}

// A guard folds as the select of its handle and an invalid-handle constant
// of its own: a known validity gives the handle or the invalid handle, and a
// validity that compares the handle itself with the invalid handle decides
// the result.
// CHECK-LABEL: func.func @guards
// CHECK-SAME: (%[[VALID:.*]]: i1, %[[HANDLE:.*]]: i64)
// CHECK-DAG: %[[INVALID:.*]] = arith.constant -1 : i64
// CHECK: %[[KEPT:.*]] = schedule.handle.guard %[[VALID]], %[[HANDLE]]
// CHECK: %[[INVALID_KEPT:.*]] = schedule.handle.guard %[[VALID]], %[[INVALID]]
// CHECK: return %[[HANDLE]], %[[INVALID]], %[[HANDLE]], %[[INVALID]], %[[KEPT]], %[[INVALID_KEPT]] :
func.func @guards(%valid: i1, %handle: i64) -> (i64, i64, i64, i64, i64, i64) {
  %true = arith.constant true
  %false = arith.constant false
  %invalid = arith.constant -1 : i64
  %a = schedule.handle.guard %true, %handle
  %b = schedule.handle.guard %false, %handle
  %live = arith.cmpi ne, %handle, %invalid : i64
  %c = schedule.handle.guard %live, %handle
  %dead = arith.cmpi eq, %invalid, %handle : i64
  %d = schedule.handle.guard %dead, %handle
  %e = schedule.handle.guard %valid, %handle
  %f = schedule.handle.guard %valid, %invalid
  return %a, %b, %c, %d, %e, %f : i64, i64, i64, i64, i64, i64
}
