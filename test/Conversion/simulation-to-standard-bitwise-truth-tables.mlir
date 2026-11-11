// RUN: talos-opt %s --convert-talos-sim-values-to-standard --canonicalize \
// RUN:   --cse | FileCheck %s --check-prefix=TABLE
// RUN: talos-opt %s --canonicalize --convert-talos-sim-values-to-standard \
// RUN:   --canonicalize --cse | FileCheck %s --check-prefix=TABLE
// RUN: talos-opt %s --convert-talos-sim-values-to-standard --cse \
// RUN:   | FileCheck %s --check-prefix=SHAPE

// IEEE 1800-2023 11.4.8, Tables 11-11 to 11-15. Each 16-lane operand pair
// enumerates every {0, 1, x, z} combination: lane i has lhs code i / 4 and rhs
// code i % 4, with codes 0, 1, x, z in that order. Z is a one value bit under
// an unknown bit and X a zero value bit, so every expected unknown lane is X.
//
//   lhs value 0xF0F0  unknown 0xFF00
//   rhs value 0xAAAA  unknown 0xCCCC
//
// The operands reach the operators through a block argument, so the first RUN
// lowers the operators before canonicalization merges the block and folds the
// lowered arithmetic. The second RUN canonicalizes first, which checks the
// simulation folders against the same tables.
// Two-state operands fold the OR's unknown plane to zero.
// TABLE-LABEL: func.func @or_from_bits(
// TABLE-SAME: %[[A:[^:]*]]: i8, %[[B:[^:]*]]: i8) -> (i8, i8)
// TABLE-DAG: %[[ZERO:.*]] = arith.constant 0 : i8
// TABLE-DAG: %[[SUM:.*]] = arith.ori %[[A]], %[[B]] : i8
// TABLE: return %[[SUM]], %[[ZERO]] : i8, i8

// TABLE-LABEL: func.func @check() -> i1
// TABLE-NEXT: %[[TRUE:.*]] = arith.constant true
// TABLE-NEXT: return %[[TRUE]] : i1

// Table 11-12 needs one OR of the unknown planes, masked by the known-one bits.
// SHAPE-LABEL: func.func @or16(
// SHAPE-SAME: %[[LV:[^:]*]]: i16, %[[LU:[^:]*]]: i16, %[[RV:[^:]*]]: i16, %[[RU:[^:]*]]: i16)
// SHAPE-DAG: %[[ONES:.*]] = arith.constant -1 : i16
// SHAPE-DAG: %[[LK:.*]] = arith.xori %[[LU]], %[[ONES]] : i16
// SHAPE-DAG: %[[RK:.*]] = arith.xori %[[RU]], %[[ONES]] : i16
// SHAPE-DAG: %[[L1:.*]] = arith.andi %[[LV]], %[[LK]] : i16
// SHAPE-DAG: %[[R1:.*]] = arith.andi %[[RV]], %[[RK]] : i16
// SHAPE-DAG: %[[KNOWN_ONE:.*]] = arith.ori %[[L1]], %[[R1]] : i16
// SHAPE-DAG: %[[ANY_UNKNOWN:.*]] = arith.ori %[[LU]], %[[RU]] : i16
// SHAPE-DAG: %[[NOT_ONE:.*]] = arith.xori %[[KNOWN_ONE]], %[[ONES]] : i16
// SHAPE: %[[UNKNOWN:.*]] = arith.andi %[[ANY_UNKNOWN]], %[[NOT_ONE]] : i16
// SHAPE-NEXT: return %[[KNOWN_ONE]], %[[UNKNOWN]] : i16, i16

module {
  func.func @or16(%l: !simulation.logic<16>, %r: !simulation.logic<16>)
      -> !simulation.logic<16> {
    %0 = simulation.logic.binary or %l, %r : !simulation.logic<16>
    return %0 : !simulation.logic<16>
  }

  func.func @or_from_bits(%a: i8, %b: i8) -> !simulation.logic<8> {
    %la = simulation.logic.from_bits %a : i8 -> !simulation.logic<8>
    %lb = simulation.logic.from_bits %b : i8 -> !simulation.logic<8>
    %0 = simulation.logic.binary or %la, %lb : !simulation.logic<8>
    return %0 : !simulation.logic<8>
  }

  func.func @check() -> i1 {
    %lhs = simulation.logic.constant 61680 : i16, 65280 : i16 : !simulation.logic<16>
    %rhs = simulation.logic.constant 43690 : i16, 52428 : i16 : !simulation.logic<16>
    %codes = simulation.logic.constant 10 : i4, 12 : i4 : !simulation.logic<4>
    // Table 11-11: rows 0 0 0 0 / 0 1 x x / 0 x x x / 0 x x x.
    %and_expected = simulation.logic.constant 32 : i16, 61120 : i16 : !simulation.logic<16>
    // Table 11-12: rows 0 1 x x / 1 1 1 1 / x 1 x x / x 1 x x.
    %or_expected = simulation.logic.constant 8946 : i16, 56588 : i16 : !simulation.logic<16>
    // Table 11-13: rows 0 1 x x / 1 0 x x / x x x x / x x x x.
    %xor_expected = simulation.logic.constant 18 : i16, 65484 : i16 : !simulation.logic<16>
    // Table 11-14: rows 1 0 x x / 0 1 x x / x x x x / x x x x.
    %xnor_expected = simulation.logic.constant 33 : i16, 65484 : i16 : !simulation.logic<16>
    // Table 11-15 on lanes 0, 1, x, z: 1, 0, x, x.
    %not_expected = simulation.logic.constant 1 : i4, 12 : i4 : !simulation.logic<4>
    cf.br ^bb1(%lhs, %rhs, %codes : !simulation.logic<16>, !simulation.logic<16>, !simulation.logic<4>)

  ^bb1(%l: !simulation.logic<16>, %r: !simulation.logic<16>, %c: !simulation.logic<4>):
    %and = simulation.logic.binary and %l, %r : !simulation.logic<16>
    %or = simulation.logic.binary or %l, %r : !simulation.logic<16>
    %xor = simulation.logic.binary xor %l, %r : !simulation.logic<16>
    %xnor = simulation.logic.binary xnor %l, %r : !simulation.logic<16>
    %not = simulation.logic.unary bit_not %c : (!simulation.logic<4>) -> !simulation.logic<4>
    %ok_and = simulation.logic.compare case_eq %and, %and_expected : (!simulation.logic<16>, !simulation.logic<16>) -> i1
    %ok_or = simulation.logic.compare case_eq %or, %or_expected : (!simulation.logic<16>, !simulation.logic<16>) -> i1
    %ok_xor = simulation.logic.compare case_eq %xor, %xor_expected : (!simulation.logic<16>, !simulation.logic<16>) -> i1
    %ok_xnor = simulation.logic.compare case_eq %xnor, %xnor_expected : (!simulation.logic<16>, !simulation.logic<16>) -> i1
    %ok_not = simulation.logic.compare case_eq %not, %not_expected : (!simulation.logic<4>, !simulation.logic<4>) -> i1
    %ok0 = arith.andi %ok_and, %ok_or : i1
    %ok1 = arith.andi %ok_xor, %ok_xnor : i1
    %ok2 = arith.andi %ok0, %ok1 : i1
    %ok = arith.andi %ok2, %ok_not : i1
    return %ok : i1
  }
}
