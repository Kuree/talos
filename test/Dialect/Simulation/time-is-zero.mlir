// RUN: talos-opt %s --canonicalize --cse --verify-each | FileCheck %s
// Zero tests fold on converted precision ticks, including real rounding.
// CHECK-LABEL: func.func @constants
// CHECK: %[[TRUE:.*]] = arith.constant true
// CHECK: %[[FALSE:.*]] = arith.constant false
// CHECK-NOT: simulation.time.
// CHECK: return %[[TRUE]], %[[FALSE]], %[[TRUE]], %[[FALSE]] : i1, i1, i1, i1
module {
  func.func @constants() -> (i1, i1, i1, i1) {
    %zero = simulation.time.constant 0
    %positive = simulation.time.constant 1
    %fraction = arith.constant 0.4 : f64
    %later = arith.constant 0.6 : f64
    %round_zero = simulation.time.from_real %fraction by 1 quantum 1
    %round_one = simulation.time.from_real %later by 1 quantum 1
    %a = simulation.time.is_zero %zero
    %b = simulation.time.is_zero %positive
    %c = simulation.time.is_zero %round_zero
    %d = simulation.time.is_zero %round_one
    return %a, %b, %c, %d : i1, i1, i1, i1
  }
}
