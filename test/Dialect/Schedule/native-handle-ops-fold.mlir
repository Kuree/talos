// RUN: talos-opt %s --canonicalize | FileCheck %s

// Constant operands offset as the runtime does (talos_rt_stable_handle_offset),
// with or without the in-bounds proof. An invalid handle, an overflowing
// offset or one its kind cannot represent gives the invalid handle -1. A
// static or automatic offset has the signed 32-bit range: a part-select that
// partly overlaps its object may start below it (IEEE 1800-2023 11.5.1).

// CHECK-LABEL: func.func @static_offsets
// CHECK-DAG: %[[NINE:.*]] = arith.constant 4611686031312289801 : i64
// CHECK-DAG: %[[BELOW:.*]] = arith.constant 4611686035607257086 : i64
// CHECK-DAG: %[[INVALID:.*]] = arith.constant -1 : i64
// CHECK-NOT: schedule.handle.offset
// CHECK: return %[[NINE]], %[[NINE]], %[[BELOW]], %[[INVALID]], %[[INVALID]] :
func.func @static_offsets() -> (i64, i64, i64, i64, i64) {
  // Static object 3 at offsets 5 and INT32_MAX.
  %root = arith.constant 4611686031312289797 : i64
  %last = arith.constant 4611686033459773439 : i64
  %invalid = arith.constant -1 : i64
  %one = arith.constant 1 : i64
  %four = arith.constant 4 : i64
  %minus7 = arith.constant -7 : i64
  %a = schedule.handle.offset %root, %four
  %b = schedule.handle.offset %root, %four in_bounds
  %c = schedule.handle.offset %root, %minus7
  %d = schedule.handle.offset %last, %one
  %e = schedule.handle.offset %invalid, %one
  return %a, %b, %c, %d, %e : i64, i64, i64, i64, i64
}

// A global offset may not go negative.
// CHECK-LABEL: func.func @other_kinds
// CHECK-DAG: %[[GLOBAL:.*]] = arith.constant 15 : i64
// CHECK-DAG: %[[AUTOMATIC:.*]] = arith.constant -9223372028264841208 : i64
// CHECK-DAG: %[[INVALID:.*]] = arith.constant -1 : i64
// CHECK-NOT: schedule.handle.offset
// CHECK: return %[[GLOBAL]], %[[INVALID]], %[[INVALID]], %[[AUTOMATIC]] :
func.func @other_kinds() -> (i64, i64, i64, i64) {
  // Global offset 10; automatic object 2 at offset 7.
  %global = arith.constant 10 : i64
  %automatic = arith.constant -9223372028264841209 : i64
  %one = arith.constant 1 : i64
  %five = arith.constant 5 : i64
  %minus11 = arith.constant -11 : i64
  %max = arith.constant 9223372036854775807 : i64
  %a = schedule.handle.offset %global, %five
  %b = schedule.handle.offset %global, %minus11
  %c = schedule.handle.offset %global, %max
  %d = schedule.handle.offset %automatic, %one
  return %a, %b, %c, %d : i64, i64, i64, i64
}

// A guard with a known validity is its handle or the invalid handle, and
// guarding the invalid handle gives it back. Offsetting by zero is no
// identity: it turns any handle the runtime cannot decode into -1.
// CHECK-LABEL: func.func @guards
// CHECK-SAME: (%[[VALID:.*]]: i1, %[[HANDLE:.*]]: i64)
// CHECK-DAG: %[[INVALID:.*]] = arith.constant -1 : i64
// CHECK-DAG: %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK: %[[KEPT:.*]] = schedule.handle.guard %[[VALID]], %[[HANDLE]]
// CHECK: %[[SAME:.*]] = schedule.handle.offset %[[HANDLE]], %[[ZERO]]
// CHECK: return %[[HANDLE]], %[[INVALID]], %[[INVALID]], %[[KEPT]], %[[SAME]] :
func.func @guards(%valid: i1, %handle: i64) -> (i64, i64, i64, i64, i64) {
  %true = arith.constant true
  %false = arith.constant false
  %invalid = arith.constant -1 : i64
  %zero = arith.constant 0 : i64
  %a = schedule.handle.guard %true, %handle
  %b = schedule.handle.guard %false, %handle
  %c = schedule.handle.guard %valid, %invalid
  %d = schedule.handle.guard %valid, %handle
  %e = schedule.handle.offset %handle, %zero
  return %a, %b, %c, %d, %e : i64, i64, i64, i64, i64
}
