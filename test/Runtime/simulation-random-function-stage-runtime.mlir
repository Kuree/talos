// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans | FileCheck %s --check-prefix=PLAN
// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans '--encode-talos-sim-to-bytecode=vpi=off' --test-talos-print-bytecode -o /dev/null 2>&1 | FileCheck %s --check-prefix=BYTECODE
// RUN: talos-opt %s --allow-unregistered-dialect --test-talos-encode-random-programs --talos-sim-compile-random-plans '--encode-talos-sim-to-bytecode=vpi=off' --convert-talos-sim-processes-to-llvm-coroutines | talos-translate --mlir-to-llvmir | %llvm_dist/bin/opt -passes='coro-early,cgscc(coro-split<reuse-storage>),coro-cleanup' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --seed=13 --execution-tier=native | FileCheck %s --check-prefix=RUNTIME
// RUN: %t.exe --seed=13 --execution-tier=bytecode | FileCheck %s --check-prefix=RUNTIME
// REQUIRES: compiled-sampler
//
// IEEE 1800-2023 18.5.11: x == f(y) and x == 0, where x is 130 bits and
// y one bit. The first stage chooses y without consulting x's constraints.
// Ordinary Simulation code executes f with a data-dependent 513/514-iteration
// loop, then a second stage treats its return as state. Both y outcomes occur;
// y == 1 fails without retrying the earlier stage. No stage publishes the
// active RNG. Wide remaining masks, failure outputs and final completion are
// checked in both execution tiers. This exercises the backend handoff; source
// constraint-call preparation is covered separately.
// PLAN: simulation.random.function_stage
// PLAN-SAME: SAMP
// PLAN: simulation.call @loop_function
// PLAN: simulation.random.function_stage
// PLAN-SAME: SAMP
// BYTECODE: intrinsic {{[0-9]+}}: id=0x00010489 inputs=8 outputs=5
// RUNTIME: function stages valid 1

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @function_stages attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 function hierarchy "check"
    simulation.code_unit.decl 3 in 0 function hierarchy "loop_function"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %zero = arith.constant 0 : i64
      %one = arith.constant 1 : i64
      %limit = arith.constant 16 : i64
      %none = arith.constant 0 : i3
      %both = arith.constant 6 : i3
      %true = arith.constant true
      cf.br ^loop(%zero, %true, %none : i64, i1, i3)
    ^loop(%index: i64, %valid: i1, %seen: i3):
      %result = simulation.call @check(%ctx, %index) : (!simulation.context, i64) -> i3
      %good = arith.trunci %result : i3 to i1
      %ok = arith.andi %valid, %good : i1
      %outcomes = arith.ori %seen, %result : i3
      %next = arith.addi %index, %one : i64
      %more = arith.cmpi ult, %next, %limit : i64
      cf.cond_br %more, ^loop(%next, %ok, %outcomes : i64, i1, i3), ^done(%ok, %outcomes : i1, i3)
    ^done(%valid_all: i1, %seen_all: i3):
      %outcome_bits = arith.andi %seen_all, %both : i3
      %saw_both = arith.cmpi eq, %outcome_bits, %both : i3
      %valid_final = arith.andi %valid_all, %saw_both : i1
      %channel = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "function stages valid %0d"
      simulation.display %ctx to %channel(%fmt, %valid_final) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i1
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %index: i64 {simulation.capture_kind = 1 : i32}) -> i3 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %start = arith.constant 680564733841876927351024328558856110097 : i131
      %mutable = arith.constant 2722258935367507707706996859454145691647 : i131
      %lower = arith.constant 1361129467683753853853498429727072845823 : i131
      %seed_stride = arith.constant 6364136223846793005 : i64
      %seed_bias = arith.constant 1442695040888963407 : i64
      %seed_product = arith.muli %index, %seed_stride : i64
      %seed = arith.addi %seed_product, %seed_bias : i64
      %increment = arith.constant 55 : i64
      %attempts = arith.constant 1 : i64
      %zero64 = arith.constant 0 : i64
      %zero130 = arith.constant 0 : i130
      %zero131 = arith.constant 0 : i131
      %shift = arith.constant 130 : i131
      %false = arith.constant false
      %active:2 = simulation.random.state %ctx : (!simulation.context) -> (i64, i64)
      %a:5 = "test.random.function_stage"(%ctx, %start, %mutable, %zero64, %attempts, %seed, %increment, %zero130) {program = [
        "version 2 width 131 instructions 7 captures 1 literals 0 flags [HAS_SOLVE_BEFORE, EXACT_UNIFORM, HAS_FUNCTION_PRIORITY]",
        "0: PUSH_VARIABLE width 130",
        "1: PUSH_CAPTURE width 130",
        "2: EQ width 1",
        "3: END_HARD width 1",
        "4: PUSH_VARIABLE width 130",
        "5: LOGICAL_NOT width 1",
        "6: END_HARD width 1 operand 1",
        "edge before 0x400000000000000000000000000000000 after 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF block 0 flags 1",
        "priority end 3 reserved 0 references 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x400000000000000000000000000000000",
        "priority end 6 reserved 0 references 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x0"]} : (!simulation.context, i131, i131, i64, i64, i64, i64, i130) -> (i131, i1, i64, i131, i1)
      %arg_wide = arith.shrui %a#0, %shift : i131
      %arg = arith.trunci %arg_wide : i131 to i64
      %returned = simulation.call @loop_function(%ctx, %arg) : (!simulation.context, i64) -> i64
      %capture = arith.extui %returned : i64 to i130
      %b:5 = "test.random.function_stage"(%ctx, %a#0, %a#3, %zero64, %attempts, %a#2, %increment, %capture) {program = [
        "version 2 width 131 instructions 7 captures 1 literals 0 flags [HAS_SOLVE_BEFORE, EXACT_UNIFORM, HAS_FUNCTION_PRIORITY]",
        "0: PUSH_VARIABLE width 130",
        "1: PUSH_CAPTURE width 130",
        "2: EQ width 1",
        "3: END_HARD width 1",
        "4: PUSH_VARIABLE width 130",
        "5: LOGICAL_NOT width 1",
        "6: END_HARD width 1 operand 1",
        "edge before 0x400000000000000000000000000000000 after 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF block 0 flags 1",
        "priority end 3 reserved 0 references 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x400000000000000000000000000000000",
        "priority end 6 reserved 0 references 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF arguments 0x0"]} : (!simulation.context, i131, i131, i64, i64, i64, i64, i130) -> (i131, i1, i64, i131, i1)
      %after:2 = simulation.random.state %ctx : (!simulation.context) -> (i64, i64)
      %lower_before = arith.andi %a#0, %lower : i131
      %lower_ok = arith.cmpi eq, %lower_before, %start : i131
      %mask_ok = arith.cmpi eq, %a#3, %lower : i131
      %unfinished = arith.cmpi eq, %a#4, %false : i1
      %expect_success = arith.cmpi eq, %arg, %zero64 : i64
      %success_ok = arith.cmpi eq, %b#1, %expect_success : i1
      %complete_ok = arith.cmpi eq, %b#4, %expect_success : i1
      %assignment_ok = arith.cmpi eq, %b#0, %zero131 : i131
      %remaining_ok = arith.cmpi eq, %b#3, %zero131 : i131
      %rng_ok = arith.cmpi eq, %b#2, %a#2 : i64
      %active_ok = arith.cmpi eq, %active#0, %after#0 : i64
      %increment_ok = arith.cmpi eq, %active#1, %after#1 : i64
      %v0 = arith.andi %lower_ok, %mask_ok : i1
      %v1 = arith.andi %unfinished, %a#1 : i1
      %v2 = arith.andi %success_ok, %complete_ok : i1
      %v3 = arith.andi %assignment_ok, %remaining_ok : i1
      %v4 = arith.andi %rng_ok, %active_ok : i1
      %v5 = arith.andi %v0, %v1 : i1
      %v6 = arith.andi %v2, %v3 : i1
      %v7 = arith.andi %v4, %increment_ok : i1
      %v8 = arith.andi %v5, %v6 : i1
      %valid = arith.andi %v8, %v7 : i1
      %zero_seen = arith.constant 2 : i3
      %one_seen = arith.constant 4 : i3
      %outcome = arith.select %expect_success, %zero_seen, %one_seen : i3
      %valid_bit = arith.extui %valid : i1 to i3
      %result = arith.ori %outcome, %valid_bit : i3
      simulation.return %result : i3
    }
    simulation.func @loop_function(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %arg: i64 {simulation.capture_kind = 1 : i32}) -> i64 attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %zero = arith.constant 0 : i64
      %one = arith.constant 1 : i64
      %base = arith.constant 513 : i64
      %limit = arith.addi %base, %arg : i64
      cf.br ^loop(%zero : i64)
    ^loop(%counter: i64):
      %next = arith.addi %counter, %one : i64
      %more = arith.cmpi ult, %next, %limit : i64
      cf.cond_br %more, ^loop(%next : i64), ^done(%next : i64)
    ^done(%count: i64):
      %odd = arith.andi %count, %one : i64
      %result = arith.xori %odd, %one : i64
      simulation.return %result : i64
    }
  }
}
