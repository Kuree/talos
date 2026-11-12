// RUN: talos-opt %s --test-talos-value-interfaces -o /dev/null 2>&1 \
// RUN:   | FileCheck %s

// Per-bit facts of logic.bitwise_mux (IEEE 1800-2023 11.4.11, Table 11-20).
// Condition bits 4..0 are a known bit of unknown value, 1, 0, X and X; the
// true operand is 1 0 0 1 1 and the false one 0 1 0 1 0. Bit 4 is known
// because both operands are, bits 3 and 2 take the selected operand's 0, bit
// 1 merges two ones to 1, and bit 0 merges 1 and 0 to X.
// CHECK: mux zero=12 one=2 known=30 {{.*}}domain=may-four-state
// Known operands give a two-state result.
// CHECK: known-mux zero=0 one=0 known=255 {{.*}}domain=two-state
module {
  simulation.design @facts {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "facts"
    simulation.func @facts(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %k: i1 {simulation.capture_kind = 2 : i32}, %p: i8 {simulation.capture_kind = 2 : i32}, %q: i8 {simulation.capture_kind = 2 : i32}, %r: i8 {simulation.capture_kind = 2 : i32}) -> (!simulation.logic<5>, !simulation.logic<8>) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %bit = simulation.logic.from_bits %k : i1 -> !simulation.logic<1>
      %low = simulation.logic.constant 8 : i4, 3 : i4 : !simulation.logic<4>
      %condition = simulation.logic.concat %bit, %low : (!simulation.logic<1>, !simulation.logic<4>) -> !simulation.logic<5>
      %a = simulation.logic.constant 19 : i5, 0 : i5 : !simulation.logic<5>
      %b = simulation.logic.constant 10 : i5, 0 : i5 : !simulation.logic<5>
      %mux = simulation.logic.bitwise_mux %condition ? %a : %b {test.fact = "mux"} : !simulation.logic<5>
      %c = simulation.logic.from_bits %p : i8 -> !simulation.logic<8>
      %t = simulation.logic.from_bits %q : i8 -> !simulation.logic<8>
      %f = simulation.logic.from_bits %r : i8 -> !simulation.logic<8>
      %known = simulation.logic.bitwise_mux %c ? %t : %f {test.fact = "known-mux"} : !simulation.logic<8>
      simulation.return %mux, %known : !simulation.logic<5>, !simulation.logic<8>
    }
  }
}
