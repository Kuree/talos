// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --test-talos-print-random-programs -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs | FileCheck %s --check-prefix=OP

// The encoder reads the printer's line format, so printing an encoded program
// reproduces its source lines: headers gain their instruction and literal
// counts, version-2 literals wider than 64 bits stay hexadecimal, and solve
// edges and priority inputs keep assignment-width masks.

// CHECK: simulation.random.solve_wide: version 1 width 8 instructions 8 captures 1 flags [HAS_SOFT, HAS_SOLVE_BEFORE, 4096]
// CHECK-NEXT:   0: PUSH_VARIABLE width 4
// CHECK-NEXT:   1: PUSH_LITERAL width 4 value 9
// CHECK-NEXT:   2: LT width 1 flags 1
// CHECK-NEXT:   3: END_HARD width 1 operand 4294967295
// CHECK-NEXT:   4: PUSH_VARIABLE width 4 operand 4
// CHECK-NEXT:   5: PUSH_CAPTURE width 4
// CHECK-NEXT:   6: EQ width 1
// CHECK-NEXT:   7: END_SOFT width 1 operand 2 auxiliary 1
// CHECK-NEXT:   edge before 0xF after 0xF0 block unmasked flags 0
// CHECK-NEXT: simulation.random.solve_wide: version 2 width 131 instructions 10 captures 1 literals 4 flags [HAS_SOLVE_BEFORE, EXACT_UNIFORM, HAS_FUNCTION_PRIORITY, HAS_FUNCTION_EDGE_ORIGINS]
// CHECK-NEXT:   0: PUSH_VARIABLE width 130
// CHECK-NEXT:   1: PUSH_LITERAL width 130 value 0x200000000000000000000000000000001
// CHECK-NEXT:   2: EQ width 1
// CHECK-NEXT:   3: END_HARD width 1
// CHECK-NEXT:   4: PUSH_VARIABLE width 1 operand 130
// CHECK-NEXT:   5: PUSH_CAPTURE width 8
// CHECK-NEXT:   6: PUSH_LITERAL width 8 value 200
// CHECK-NEXT:   7: LT width 1
// CHECK-NEXT:   8: LOGICAL_AND width 1
// CHECK-NEXT:   9: END_HARD width 1 operand 1
// CHECK-NEXT:   edge before 0x400000000000000000000000000000000 after 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF block 0 flags 9
// CHECK-NEXT:   priority end 3 reserved 0 references 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x0
// CHECK-NEXT:   priority end 9 reserved 0 references 0x400000000000000000000000000000000 arguments 0x400000000000000000000000000000000

// The replacement is the registered op with the encoded little-endian bytes.
// OP-LABEL: func.func @programs
// OP: simulation.random.solve_wide
// OP-SAME: {program = "ODR1\01\00\18\00\08\00\00\00\08\00\00\00\01\00\00\00\03\10\00\00
// OP: simulation.random.solve_wide
// OP-SAME: {program = "ODR1\02\00 \00\83\00\00\00\0A\00\00\00\01\00\00\00b\08\00\00\04\00\00\00\00\00\00\00

func.func @programs(%ctx: !simulation.context, %v: i8, %w: i131, %s: i64) {
  %a:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 1 flags [HAS_SOFT, HAS_SOLVE_BEFORE, 4096]",
    "0: PUSH_VARIABLE width 4",
    "1: PUSH_LITERAL width 4 value 9",
    "2: LT width 1 flags 1",
    "3: END_HARD width 1 operand 4294967295",
    "4: PUSH_VARIABLE width 4 operand 4",
    "5: PUSH_CAPTURE width 4",
    "6: EQ width 1",
    "7: END_SOFT width 1 operand 2 auxiliary 1",
    "edge before 0xF after 0xF0 block unmasked flags 0"]} : (!simulation.context, i8, i8, i64, i64, i64, i64, i64) -> (i8, i1, i64)
  %b:3 = "test.random.solve_wide"(%ctx, %w, %w, %s, %s, %s, %s, %s) {program = [
    "version 2 width 131 captures 1 flags [HAS_SOLVE_BEFORE, EXACT_UNIFORM, HAS_FUNCTION_PRIORITY, HAS_FUNCTION_EDGE_ORIGINS]",
    "PUSH_VARIABLE width 130",
    "PUSH_LITERAL width 130 value 0x200000000000000000000000000000001",
    "EQ width 1",
    "END_HARD width 1",
    "PUSH_VARIABLE width 1 operand 130",
    "PUSH_CAPTURE width 8",
    "PUSH_LITERAL width 8 value 200",
    "LT width 1",
    "LOGICAL_AND width 1",
    "END_HARD width 1 operand 1",
    "edge before 0x400000000000000000000000000000000 after 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF block 0 flags 9",
    "priority end 3 reserved 0 references 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x0",
    "priority end 9 reserved 0 references 0x400000000000000000000000000000000 arguments 0x400000000000000000000000000000000"]} : (!simulation.context, i131, i131, i64, i64, i64, i64, i64) -> (i131, i1, i64)
  return
}
