// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans | FileCheck %s --check-prefix=PLAN
// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans --talos-sim-compile-random-plans --mlir-print-ir-after=talos-sim-compile-random-plans --mlir-print-ir-after-change -o /dev/null 2>&1 | FileCheck %s --check-prefix=ONCE --implicit-check-not='IR Dump After'
// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans '--encode-talos-sim-to-bytecode=vpi=off' --convert-talos-sim-processes-to-llvm-coroutines | talos-translate --mlir-to-llvmir | %llvm_dist/bin/opt -passes='coro-early,cgscc(coro-split<reuse-storage>),coro-cleanup' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --seed=13 | FileCheck %s --check-prefix=RUNTIME
// REQUIRES: compiled-sampler
//
// IEEE 1800-2023 18.4.1: typed real programs run only from exact compiled
// plans. The pass attaches a SAMP bundle to every typed program in both the
// narrow and the wide solve op, and a second application changes nothing.
// PLAN: simulation.random.solve
// PLAN-SAME: SAMP
// PLAN: simulation.random.solve_wide
// PLAN-SAME: SAMP
// ONCE: IR Dump After
//
// The random input is an eight-bit selector for adjacent IEEE values. Every
// endpoint and halfway neighbor, out-of-range captures, frozen assignments and
// constraint modes are checked against the plan: RNE, signed zero, NaN, infinity, conversions,
// selection, soft priorities and both numeric rank precisions. Each successful
// call has one accepted selector and needs no RNG draw. The wide program also
// decodes an interior coordinate in each selected real cell.
// RUNTIME: real compiler plans valid 1

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @real_plans attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 function hierarchy "narrow"
    simulation.code_unit.decl 3 in 0 function hierarchy "wide"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %first = arith.constant -1 : i64
      %one = arith.constant 1 : i64
      %low_neighbor = arith.constant 126 : i64
      %high_neighbor = arith.constant 129 : i64
      %last_neighbor = arith.constant 254 : i64
      %limit = arith.constant 257 : i64
      %mask = arith.constant 255 : i64
      %none = arith.constant 0 : i64
      %forty_two = arith.constant 42 : i64
      %forty_one = arith.constant 41 : i64
      %true = arith.constant true
      cf.br ^loop(%first, %true : i64, i1)
    ^loop(%wanted: i64, %valid: i1):
      %n = simulation.call @narrow(%ctx, %wanted, %mask, %none) : (!simulation.context, i64, i64, i64) -> i1
      %w = simulation.call @wide(%ctx, %wanted, %mask, %none) : (!simulation.context, i64, i64, i64) -> i1
      %ok0 = arith.andi %n, %w : i1
      %ok = arith.andi %ok0, %valid : i1
      // Visit -1, 0, 1, 126, 127, 128, 129, 254, 255, 256. Interior
      // selectors repeat the same decoder; endpoints and ties suffice.
      %successor = arith.addi %wanted, %one : i64
      %skip_low = arith.cmpi eq, %wanted, %one : i64
      %skip_high = arith.cmpi eq, %wanted, %high_neighbor : i64
      %next_low = arith.select %skip_low, %low_neighbor, %successor : i64
      %next = arith.select %skip_high, %last_neighbor, %next_low : i64
      %more = arith.cmpi slt, %next, %limit : i64
      cf.cond_br %more, ^loop(%next, %ok : i64, i1), ^done(%ok : i1)
    ^done(%valid_all: i1):
      %f0 = simulation.call @narrow(%ctx, %forty_two, %none, %none) : (!simulation.context, i64, i64, i64) -> i1
      %f1 = simulation.call @wide(%ctx, %forty_one, %none, %none) : (!simulation.context, i64, i64, i64) -> i1
      %m0 = simulation.call @narrow(%ctx, %forty_two, %mask, %one) : (!simulation.context, i64, i64, i64) -> i1
      %m1 = simulation.call @wide(%ctx, %forty_one, %none, %one) : (!simulation.context, i64, i64, i64) -> i1
      %v0 = arith.andi %f0, %f1 : i1
      %v1 = arith.andi %m0, %m1 : i1
      %v2 = arith.andi %v0, %v1 : i1
      %good = arith.andi %valid_all, %v2 : i1
      %channel = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "real compiler plans valid %0d"
      simulation.display %ctx to %channel(%fmt, %good) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i1
      simulation.return
    }
    simulation.func @narrow(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %wanted: i64 {simulation.capture_kind = 1 : i32}, %mask: i64 {simulation.capture_kind = 1 : i32}, %disabled: i64 {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %start = arith.constant 42 : i64
      %seed = arith.constant 13 : i64
      %increment = arith.constant 55 : i64
      %attempts = arith.constant 1 : i64
      %zero = arith.constant 0 : i64
      %bound = arith.constant 256 : i64
      %fixed = arith.constant 42 : i64
      %r:3 = "test.random.solve"(%ctx, %start, %mask, %disabled, %attempts, %seed, %increment, %wanted) {program = [
        "version 1 width 8 instructions 113 captures 1 flags [HAS_SOFT, EXACT_UNIFORM, HAS_REAL]",
        "0: PUSH_VARIABLE width 8",
        "1: CAST width 32",
        "2: PUSH_LITERAL width 32 value 1065353216",
        "3: ADD width 32",
        "4: REAL32_BITS width 32",
        "5: STORE_VALUE width 32",
        "6: PUSH_CAPTURE width 32",
        "7: PUSH_LITERAL width 32 value 1065353216",
        "8: ADD width 32",
        "9: REAL32_BITS width 32",
        "10: EQ width 1",
        "11: END_HARD width 1",
        "12: PUSH_CAPTURE width 64",
        "13: PUSH_LITERAL width 64 value 0",
        "14: GE width 1 flags 1",
        "15: PUSH_CAPTURE width 64",
        "16: PUSH_LITERAL width 64 value 256",
        "17: LT width 1 flags 1",
        "18: LOGICAL_AND width 1",
        "19: END_HARD width 1 operand 4294967295",
        "20: LOAD_VALUE width 32",
        "21: LOAD_VALUE width 32",
        "22: DIV width 32",
        "23: PUSH_LITERAL width 32 value 1065353216",
        "24: REAL32_BITS width 32",
        "25: EQ width 1",
        "26: END_HARD width 1 operand 4294967295",
        "27: LOAD_VALUE width 32",
        "28: NEG width 32",
        "29: LOAD_VALUE width 32",
        "30: ADD width 32",
        "31: PUSH_LITERAL width 32 value 2147483648",
        "32: REAL32_BITS width 32",
        "33: EQ width 1",
        "34: END_HARD width 1 operand 4294967295",
        "35: PUSH_LITERAL width 32 value 2147483648",
        "36: REAL32_BITS width 32",
        "37: LOGICAL_NOT width 1",
        "38: END_HARD width 1 operand 4294967295",
        "39: PUSH_LITERAL width 32 value 2143294004",
        "40: REAL32_BITS width 32",
        "41: PUSH_LITERAL width 32 value 2143294004",
        "42: REAL32_BITS width 32",
        "43: NE width 1",
        "44: END_HARD width 1 operand 4294967295",
        "45: PUSH_LITERAL width 32 value 1065353216",
        "46: REAL32_BITS width 32",
        "47: PUSH_LITERAL width 32 value 0",
        "48: REAL32_BITS width 32",
        "49: DIV width 32",
        "50: LOAD_VALUE width 32",
        "51: GT width 1",
        "52: END_HARD width 1 operand 4294967295",
        "53: LOAD_VALUE width 32",
        "54: REAL_CAST width 64",
        "55: PUSH_VARIABLE width 8",
        "56: REAL_CAST width 64",
        "57: PUSH_LITERAL width 64 value 4710765210229538816",
        "58: REAL64_BITS width 64",
        "59: DIV width 64",
        "60: PUSH_LITERAL width 64 value 4607182418800017408",
        "61: REAL64_BITS width 64",
        "62: ADD width 64",
        "63: EQ width 1",
        "64: END_HARD width 1 operand 4294967295",
        "65: PUSH_LITERAL width 8 value 255",
        "66: REAL_CAST width 64 flags 1",
        "67: PUSH_LITERAL width 64 value 13830554455654793216",
        "68: REAL64_BITS width 64",
        "69: EQ width 1",
        "70: END_HARD width 1 operand 4294967295",
        "71: PUSH_LITERAL width 64 value 9223372036854775808",
        "72: REAL64_BITS width 64",
        "73: NEG width 64",
        "74: REAL_TO_BITS width 64",
        "75: PUSH_LITERAL width 64 value 0",
        "76: EQ width 1",
        "77: END_HARD width 1 operand 4294967295",
        "78: PUSH_LITERAL width 32 value 2143294004",
        "79: REAL32_BITS width 32",
        "80: REAL_TO_BITS width 32",
        "81: PUSH_LITERAL width 32 value 2143294004",
        "82: EQ width 1",
        "83: END_HARD width 1 operand 4294967295",
        "84: PUSH_LITERAL width 32 value 1065353216",
        "85: REAL32_BITS width 32",
        "86: PUSH_LITERAL width 32 value 864026624",
        "87: REAL32_BITS width 32",
        "88: ADD width 32",
        "89: PUSH_LITERAL width 32 value 1065353216",
        "90: REAL32_BITS width 32",
        "91: EQ width 1",
        "92: END_HARD width 1 operand 4294967295",
        "93: PUSH_LITERAL width 1 value 0",
        "94: PUSH_LITERAL width 64 value 4607182418800017408",
        "95: REAL64_BITS width 64",
        "96: PUSH_LITERAL width 64 value 9223372036854775808",
        "97: REAL64_BITS width 64",
        "98: SELECT width 64",
        "99: REAL_TO_BITS width 64",
        "100: PUSH_LITERAL width 64 value 9223372036854775808",
        "101: EQ width 1",
        "102: END_HARD width 1 operand 4294967295",
        "103: LOAD_VALUE width 32",
        "104: PUSH_LITERAL width 32 value 1065353216",
        "105: REAL32_BITS width 32",
        "106: GT width 1",
        "107: END_SOFT width 1 operand 4294967295",
        "108: LOAD_VALUE width 32",
        "109: PUSH_LITERAL width 32 value 1065353216",
        "110: REAL32_BITS width 32",
        "111: EQ width 1",
        "112: END_SOFT width 1 operand 4294967295 auxiliary 1"]} : (!simulation.context, i64, i64, i64, i64, i64, i64, i64) -> (i64, i1, i64)
      %assignment = arith.ori %r#0, %zero : i64
      %nonnegative = arith.cmpi sge, %wanted, %zero : i64
      %in_range = arith.cmpi slt, %wanted, %bound : i64
      %valid_wanted = arith.andi %nonnegative, %in_range : i1
      %frozen = arith.cmpi eq, %mask, %zero : i64
      %matches_fixed = arith.cmpi eq, %wanted, %fixed : i64
      %mode_off = arith.cmpi ne, %disabled, %zero : i64
      %constraint_ok = arith.ori %matches_fixed, %mode_off : i1
      %true = arith.constant true
      %available = arith.select %frozen, %constraint_ok, %true : i1
      %expect_success = arith.andi %valid_wanted, %available : i1
      %active_value = arith.select %mode_off, %zero, %wanted : i64
      %success_value = arith.select %frozen, %fixed, %active_value : i64
      %expect_assignment = arith.select %expect_success, %success_value, %zero : i64
      %s_ok = arith.cmpi eq, %r#1, %expect_success : i1
      %a_ok = arith.cmpi eq, %assignment, %expect_assignment : i64
      %rng_ok = arith.cmpi eq, %r#2, %seed : i64
      %ok0 = arith.andi %s_ok, %a_ok : i1
      %ok = arith.andi %ok0, %rng_ok : i1
      simulation.return %ok : i1
    }
    simulation.func @wide(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %wanted: i64 {simulation.capture_kind = 1 : i32}, %mask: i64 {simulation.capture_kind = 1 : i32}, %disabled: i64 {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %start = arith.constant 42 : i8
      %seed = arith.constant 13 : i64
      %increment = arith.constant 55 : i64
      %attempts = arith.constant 1 : i64
      %zero = arith.constant 0 : i64
      %bound = arith.constant 256 : i64
      %fixed = arith.constant 42 : i64
      %mutable = arith.trunci %mask : i64 to i8
      %r:3 = "test.random.solve_wide"(%ctx, %start, %mutable, %disabled, %attempts, %seed, %increment, %wanted) {program = [
        "version 2 width 8 instructions 165 captures 1 literals 184 flags [HAS_SOFT, EXACT_UNIFORM, HAS_REAL]",
        "0: PUSH_VARIABLE width 8",
        "1: CAST width 32",
        "2: PUSH_LITERAL width 32 value 1065353216",
        "3: ADD width 32",
        "4: REAL32_BITS width 32",
        "5: STORE_VALUE width 32",
        "6: PUSH_CAPTURE width 32",
        "7: PUSH_LITERAL width 32 value 1065353216",
        "8: ADD width 32",
        "9: REAL32_BITS width 32",
        "10: EQ width 1",
        "11: END_HARD width 1",
        "12: PUSH_CAPTURE width 64",
        "13: PUSH_LITERAL width 64 value 0",
        "14: GE width 1 flags 1",
        "15: PUSH_CAPTURE width 64",
        "16: PUSH_LITERAL width 64 value 256",
        "17: LT width 1 flags 1",
        "18: LOGICAL_AND width 1",
        "19: END_HARD width 1 operand 4294967295",
        "20: LOAD_VALUE width 32",
        "21: LOAD_VALUE width 32",
        "22: DIV width 32",
        "23: PUSH_LITERAL width 32 value 1065353216",
        "24: REAL32_BITS width 32",
        "25: EQ width 1",
        "26: END_HARD width 1 operand 4294967295",
        "27: LOAD_VALUE width 32",
        "28: NEG width 32",
        "29: LOAD_VALUE width 32",
        "30: ADD width 32",
        "31: PUSH_LITERAL width 32 value 2147483648",
        "32: REAL32_BITS width 32",
        "33: EQ width 1",
        "34: END_HARD width 1 operand 4294967295",
        "35: PUSH_LITERAL width 32 value 2147483648",
        "36: REAL32_BITS width 32",
        "37: LOGICAL_NOT width 1",
        "38: END_HARD width 1 operand 4294967295",
        "39: PUSH_LITERAL width 32 value 2143294004",
        "40: REAL32_BITS width 32",
        "41: PUSH_LITERAL width 32 value 2143294004",
        "42: REAL32_BITS width 32",
        "43: NE width 1",
        "44: END_HARD width 1 operand 4294967295",
        "45: PUSH_LITERAL width 32 value 1065353216",
        "46: REAL32_BITS width 32",
        "47: PUSH_LITERAL width 32 value 0",
        "48: REAL32_BITS width 32",
        "49: DIV width 32",
        "50: LOAD_VALUE width 32",
        "51: GT width 1",
        "52: END_HARD width 1 operand 4294967295",
        "53: LOAD_VALUE width 32",
        "54: REAL_CAST width 64",
        "55: PUSH_VARIABLE width 8",
        "56: REAL_CAST width 64",
        "57: PUSH_LITERAL width 64 value 4710765210229538816",
        "58: REAL64_BITS width 64",
        "59: DIV width 64",
        "60: PUSH_LITERAL width 64 value 4607182418800017408",
        "61: REAL64_BITS width 64",
        "62: ADD width 64",
        "63: EQ width 1",
        "64: END_HARD width 1 operand 4294967295",
        "65: PUSH_LITERAL width 8 value 255",
        "66: REAL_CAST width 64 flags 1",
        "67: PUSH_LITERAL width 64 value 13830554455654793216",
        "68: REAL64_BITS width 64",
        "69: EQ width 1",
        "70: END_HARD width 1 operand 4294967295",
        "71: PUSH_LITERAL width 64 value 9223372036854775808",
        "72: REAL64_BITS width 64",
        "73: NEG width 64",
        "74: REAL_TO_BITS width 64",
        "75: PUSH_LITERAL width 64 value 0",
        "76: EQ width 1",
        "77: END_HARD width 1 operand 4294967295",
        "78: PUSH_LITERAL width 32 value 2143294004",
        "79: REAL32_BITS width 32",
        "80: REAL_TO_BITS width 32",
        "81: PUSH_LITERAL width 32 value 2143294004",
        "82: EQ width 1",
        "83: END_HARD width 1 operand 4294967295",
        "84: PUSH_LITERAL width 32 value 1065353216",
        "85: REAL32_BITS width 32",
        "86: PUSH_LITERAL width 32 value 864026624",
        "87: REAL32_BITS width 32",
        "88: ADD width 32",
        "89: PUSH_LITERAL width 32 value 1065353216",
        "90: REAL32_BITS width 32",
        "91: EQ width 1",
        "92: END_HARD width 1 operand 4294967295",
        "93: PUSH_LITERAL width 1 value 0",
        "94: PUSH_LITERAL width 64 value 4607182418800017408",
        "95: REAL64_BITS width 64",
        "96: PUSH_LITERAL width 64 value 9223372036854775808",
        "97: REAL64_BITS width 64",
        "98: SELECT width 64",
        "99: REAL_TO_BITS width 64",
        "100: PUSH_LITERAL width 64 value 9223372036854775808",
        "101: EQ width 1",
        "102: END_HARD width 1 operand 4294967295",
        "103: PUSH_VARIABLE width 8",
        "104: CAST width 279",
        "105: PUSH_LITERAL width 279 value 0x7F",
        "106: SHIFT_LEFT width 279",
        "107: PUSH_LITERAL width 279 value 0x40000000000000000000000000000000000000",
        "108: ADD width 279",
        "109: PUSH_LITERAL width 279 value 0x1",
        "110: ADD width 279",
        "111: STORE_VALUE width 279 operand 1",
        "112: REAL_RANK_VALID width 1",
        "113: END_HARD width 1 operand 4294967295",
        "114: LOAD_VALUE width 279 operand 1",
        "115: REAL32_FROM_RANK width 32",
        "116: PUSH_VARIABLE width 8",
        "117: CAST width 32",
        "118: PUSH_LITERAL width 32 value 1065353216",
        "119: ADD width 32",
        "120: REAL32_BITS width 32",
        "121: EQ width 1",
        "122: END_HARD width 1 operand 4294967295",
        "123: PUSH_LITERAL width 279 value 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
        "124: REAL32_FROM_RANK width 32",
        "125: REAL_TO_BITS width 32",
        "126: PUSH_LITERAL width 32 value 2147483648",
        "127: EQ width 1",
        "128: END_HARD width 1 operand 4294967295",
        "129: PUSH_VARIABLE width 8",
        "130: CAST width 2100",
        "131: PUSH_LITERAL width 2100 value 0x3FF",
        "132: SHIFT_LEFT width 2100",
        "133: PUSH_LITERAL width 2100 value 0x80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "134: ADD width 2100",
        "135: PUSH_LITERAL width 2100 value 0x1",
        "136: ADD width 2100",
        "137: STORE_VALUE width 2100 operand 2",
        "138: REAL_RANK_VALID width 1",
        "139: END_HARD width 1 operand 4294967295",
        "140: LOAD_VALUE width 2100 operand 2",
        "141: REAL64_FROM_RANK width 64",
        "142: PUSH_VARIABLE width 8",
        "143: CAST width 64",
        "144: PUSH_LITERAL width 64 value 4607182418800017408",
        "145: ADD width 64",
        "146: REAL64_BITS width 64",
        "147: EQ width 1",
        "148: END_HARD width 1 operand 4294967295",
        "149: PUSH_LITERAL width 2100 value 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
        "150: REAL64_FROM_RANK width 64",
        "151: REAL_TO_BITS width 64",
        "152: PUSH_LITERAL width 64 value 9223372036854775808",
        "153: EQ width 1",
        "154: END_HARD width 1 operand 4294967295",
        "155: LOAD_VALUE width 32",
        "156: PUSH_LITERAL width 32 value 1065353216",
        "157: REAL32_BITS width 32",
        "158: GT width 1",
        "159: END_SOFT width 1 operand 4294967295",
        "160: LOAD_VALUE width 32",
        "161: PUSH_LITERAL width 32 value 1065353216",
        "162: REAL32_BITS width 32",
        "163: EQ width 1",
        "164: END_SOFT width 1 operand 4294967295 auxiliary 1"]} : (!simulation.context, i8, i8, i64, i64, i64, i64, i64) -> (i8, i1, i64)
      %assignment = arith.extui %r#0 : i8 to i64
      %nonnegative = arith.cmpi sge, %wanted, %zero : i64
      %in_range = arith.cmpi slt, %wanted, %bound : i64
      %valid_wanted = arith.andi %nonnegative, %in_range : i1
      %frozen = arith.cmpi eq, %mask, %zero : i64
      %matches_fixed = arith.cmpi eq, %wanted, %fixed : i64
      %mode_off = arith.cmpi ne, %disabled, %zero : i64
      %constraint_ok = arith.ori %matches_fixed, %mode_off : i1
      %true = arith.constant true
      %available = arith.select %frozen, %constraint_ok, %true : i1
      %expect_success = arith.andi %valid_wanted, %available : i1
      %active_value = arith.select %mode_off, %zero, %wanted : i64
      %success_value = arith.select %frozen, %fixed, %active_value : i64
      %expect_assignment = arith.select %expect_success, %success_value, %zero : i64
      %s_ok = arith.cmpi eq, %r#1, %expect_success : i1
      %a_ok = arith.cmpi eq, %assignment, %expect_assignment : i64
      %rng_ok = arith.cmpi eq, %r#2, %seed : i64
      %ok0 = arith.andi %s_ok, %a_ok : i1
      %ok = arith.andi %ok0, %rng_ok : i1
      simulation.return %ok : i1
    }
  }
}
