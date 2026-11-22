// RUN: talos-opt %s --loop-invariant-code-motion | FileCheck %s

// An offset proved in bounds holds its proof only where it was made, under
// the guards of its selection; here, inside a loop that may run no
// iteration. Loop-invariant code motion hoists the unproved offset, a total
// function of its operands, but leaves the proved one in the loop: it is not
// speculatable (IEEE 1800-2023 7.4.5, 11.5.1).
// CHECK-LABEL: func.func @loop(
// CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64, %[[COUNT:.*]]: index)
// CHECK: %[[UNPROVED:.*]] = schedule.handle.offset %[[ROOT]], %[[INDEX]]{{$}}
// CHECK-NEXT: scf.for
// CHECK-NEXT: %[[PROVED:.*]] = schedule.handle.offset %[[ROOT]], %[[INDEX]] in_bounds
// CHECK-NEXT: func.call @use(%[[UNPROVED]], %[[PROVED]])
func.func private @use(i64, i64)
func.func @loop(%root: i64, %index: i64, %count: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %count step %c1 {
    %unproved = schedule.handle.offset %root, %index
    %proved = schedule.handle.offset %root, %index in_bounds
    func.call @use(%unproved, %proved) : (i64, i64) -> ()
  }
  return
}
