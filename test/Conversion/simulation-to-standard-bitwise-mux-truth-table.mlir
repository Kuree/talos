// RUN: talos-opt %s --convert-talos-sim-values-to-standard --canonicalize \
// RUN:   --cse | FileCheck %s --check-prefix=TABLE
// RUN: talos-opt %s --canonicalize --convert-talos-sim-values-to-standard \
// RUN:   --canonicalize --cse | FileCheck %s --check-prefix=TABLE
// RUN: talos-opt %s --convert-talos-sim-values-to-standard --canonicalize \
// RUN:   --cse | FileCheck %s --check-prefix=SHAPE

// IEEE 1800-2023 11.4.11 per bit. The 64 lanes enumerate every {0, 1, x, z}
// triple: lane i has condition code i / 16, true code (i / 4) % 4 and false
// code i % 4, with codes 0, 1, x, z in that order (Z is a one value bit under
// an unknown bit, X a zero one). A known condition bit selects the operand
// bit, Z included; an X or Z condition bit keeps a common known 0 or 1 and is
// X otherwise (Table 11-20).
//
//   condition value 0xffff0000ffff0000  unknown 0xffffffff00000000
//   true      value 0xf0f0f0f0f0f0f0f0  unknown 0xff00ff00ff00ff00
//   false     value 0xaaaaaaaaaaaaaaaa  unknown 0xcccccccccccccccc
//   result    value 0x00200020f0f0aaaa  unknown 0xffdeffdeff00cccc
//
// The operands reach the operator through a block argument, so the first RUN
// lowers it before canonicalization folds the lowered arithmetic; the second
// canonicalizes first, which checks the folder against the same table.

// Known operands select value bits only.
// TABLE-LABEL: func.func @two_state(
// TABLE-SAME: %[[C:[^:]*]]: i8, %[[A:[^:]*]]: i8, %[[B:[^:]*]]: i8) -> (i8, i8)
// TABLE-DAG: %[[ZERO:.*]] = arith.constant 0 : i8
// TABLE-DAG: %[[ONES:.*]] = arith.constant -1 : i8
// TABLE-DAG: %[[NC:.*]] = arith.xori %[[C]], %[[ONES]] : i8
// TABLE-DAG: %[[TAKE_A:.*]] = arith.andi %[[C]], %[[A]] : i8
// TABLE-DAG: %[[TAKE_B:.*]] = arith.andi %[[NC]], %[[B]] : i8
// TABLE-DAG: %[[R:.*]] = arith.ori %[[TAKE_A]], %[[TAKE_B]] : i8
// TABLE: return %[[R]], %[[ZERO]] : i8, i8

// TABLE-LABEL: func.func @check() -> i1
// TABLE-NEXT: %[[TRUE:.*]] = arith.constant true
// TABLE-NEXT: return %[[TRUE]] : i1

// One word per plane, no per-bit code.
// SHAPE-LABEL: func.func @mux64(
// SHAPE-NOT: arith.select
// SHAPE-NOT: arith.extui
// SHAPE: return {{.*}} : i64, i64

module {
  func.func @mux64(%c: !simulation.logic<64>, %a: !simulation.logic<64>,
                   %b: !simulation.logic<64>) -> !simulation.logic<64> {
    %0 = simulation.logic.bitwise_mux %c ? %a : %b : !simulation.logic<64>
    return %0 : !simulation.logic<64>
  }

  func.func @two_state(%c: i8, %a: i8, %b: i8) -> !simulation.logic<8> {
    %lc = simulation.logic.from_bits %c : i8 -> !simulation.logic<8>
    %la = simulation.logic.from_bits %a : i8 -> !simulation.logic<8>
    %lb = simulation.logic.from_bits %b : i8 -> !simulation.logic<8>
    %0 = simulation.logic.bitwise_mux %lc ? %la : %lb : !simulation.logic<8>
    return %0 : !simulation.logic<8>
  }

  func.func @check() -> i1 {
    %condition = simulation.logic.constant 0xffff0000ffff0000 : i64, 0xffffffff00000000 : i64 : !simulation.logic<64>
    %true_value = simulation.logic.constant 0xf0f0f0f0f0f0f0f0 : i64, 0xff00ff00ff00ff00 : i64 : !simulation.logic<64>
    %false_value = simulation.logic.constant 0xaaaaaaaaaaaaaaaa : i64, 0xcccccccccccccccc : i64 : !simulation.logic<64>
    %expected = simulation.logic.constant 0x00200020f0f0aaaa : i64, 0xffdeffdeff00cccc : i64 : !simulation.logic<64>
    cf.br ^bb1(%condition, %true_value, %false_value : !simulation.logic<64>, !simulation.logic<64>, !simulation.logic<64>)

  ^bb1(%c: !simulation.logic<64>, %a: !simulation.logic<64>, %b: !simulation.logic<64>):
    %mux = simulation.logic.bitwise_mux %c ? %a : %b : !simulation.logic<64>
    %ok = simulation.logic.compare case_eq %mux, %expected : (!simulation.logic<64>, !simulation.logic<64>) -> i1
    return %ok : i1
  }
}
