// RUN: talos-opt %s --canonicalize | FileCheck %s

// A handle offset does not fold constant operands, like the runtime call it
// stands for: producers offset constants when they create it. An offset by
// zero is its handle, since the runtime re-encodes a stable handle unchanged
// and keeps the invalid handle. It reads and writes no state (an invalid
// selection is its invalid-handle result, IEEE 1800-2023 7.4.5, 11.5.1), so
// an unused one goes away, proved in bounds or not.
// CHECK-LABEL: func.func @offsets
// CHECK-SAME: (%[[HANDLE:.*]]: i64, %{{.*}}: i64)
// CHECK-DAG: %[[ROOT:.*]] = arith.constant 4611686031312289797 : i64
// CHECK-DAG: %[[FOUR:.*]] = arith.constant 4 : i64
// CHECK: %[[CONSTANT:.*]] = schedule.handle.offset %[[ROOT]], %[[FOUR]]
// CHECK-NOT: schedule.handle.offset
// CHECK: return %[[CONSTANT]], %[[HANDLE]], %[[HANDLE]] :
func.func @offsets(%handle: i64, %amount: i64) -> (i64, i64, i64) {
  // Static object 3 at offset 5.
  %root = arith.constant 4611686031312289797 : i64
  %four = arith.constant 4 : i64
  %zero = arith.constant 0 : i64
  %constant = schedule.handle.offset %root, %four
  %same = schedule.handle.offset %handle, %zero
  %proved = schedule.handle.offset %handle, %zero in_bounds
  %unused = schedule.handle.offset %handle, %amount
  %unused_proved = schedule.handle.offset %handle, %amount in_bounds
  return %constant, %same, %proved : i64, i64, i64
}

// An offset proved in bounds of one proved in bounds is one offset by the sum
// of the amounts, proved in bounds. Without both proofs the runtime checks
// each step, so the chain stays.
// CHECK-LABEL: func.func @chains
// CHECK-SAME: (%[[HANDLE:.*]]: i64, %[[INDEX:.*]]: i64, %[[FIELD:.*]]: i64)
// CHECK-DAG: %[[FIVE:.*]] = arith.constant 5 : i64
// CHECK-DAG: %[[TWO:.*]] = arith.constant 2 : i64
// CHECK-DAG: %[[THREE:.*]] = arith.constant 3 : i64
// CHECK-DAG: %[[CONSTANT:.*]] = schedule.handle.offset %[[HANDLE]], %[[FIVE]] in_bounds
// CHECK-DAG: %[[SUM:.*]] = arith.addi %[[INDEX]], %[[FIELD]] : i64
// CHECK-DAG: %[[MERGED:.*]] = schedule.handle.offset %[[HANDLE]], %[[SUM]] in_bounds
// CHECK-DAG: %[[ELEMENT:.*]] = schedule.handle.offset %[[HANDLE]], %[[INDEX]]{{$}}
// CHECK-DAG: %[[UNPROVED:.*]] = schedule.handle.offset %[[ELEMENT]], %[[THREE]] in_bounds
// CHECK-DAG: %[[PROVED:.*]] = schedule.handle.offset %[[HANDLE]], %[[TWO]] in_bounds
// CHECK-DAG: %[[OUTER:.*]] = schedule.handle.offset %[[PROVED]], %[[FIELD]]{{$}}
// CHECK: return %[[CONSTANT]], %[[MERGED]], %[[UNPROVED]], %[[OUTER]] :
func.func @chains(%handle: i64, %index: i64, %field: i64)
    -> (i64, i64, i64, i64) {
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %a = schedule.handle.offset %handle, %two in_bounds
  %constant = schedule.handle.offset %a, %three in_bounds
  %b = schedule.handle.offset %handle, %index in_bounds
  %merged = schedule.handle.offset %b, %field in_bounds
  %element = schedule.handle.offset %handle, %index
  %unproved = schedule.handle.offset %element, %three in_bounds
  %proved = schedule.handle.offset %handle, %two in_bounds
  %outer = schedule.handle.offset %proved, %field
  return %constant, %merged, %unproved, %outer : i64, i64, i64, i64
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
