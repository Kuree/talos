// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir
// RUN: FileCheck %s < %t.mlir

// A write on one predecessor changes the control before its joined read.
// An entry-false value cannot exclude the later payload access. A future
// analysis may safely forward the write's SSA value instead; runtime tests
// check behavior without forbidding that valid refinement (LRM4.6/4.7).
// CHECK: llvm.func @__talos_direct_fragment_

module attributes {
  native.closed_executable,
  schedule.native.max_inline_ops = 16 : i64,
  schedule.native_scheduler = 3 : i32,
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @conditional_prefix {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : !simulation.logic<8> design
    simulation.storage.decl 3 in 0 : !simulation.logic<8> design
    simulation.storage.decl 4 in 0 : !simulation.logic<8> design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "lane"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %levels = arith.constant 0 : i64
      %scope = simulation.bytes.constant ""
      simulation.dump.vars %ctx, %levels, %scope : (!simulation.context, i64, !simulation.bytes) -> ()
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      %lane = simulation.spawn @lane(%ctx, %clk) : !simulation.context, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }
    simulation.func @clock(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      %old = simulation.ref.load %clk : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %next = simulation.logic.unary bit_not %old : (!simulation.logic<1>) -> !simulation.logic<1>
      simulation.ref.store %next to %clk : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      cf.br ^wait
    }
    simulation.func @lane(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.ref<!simulation.logic<1>>
    ^body:
      %choose_ref = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %choose = simulation.ref.load %choose_ref : !simulation.ref<i1> -> i1
      cf.cond_br %choose, ^write, ^join
    ^write:
      %write_ref = simulation.context.storage %ctx[5] : !simulation.ref<i1>
      %true = arith.constant true
      simulation.ref.store %true to %write_ref : i1, !simulation.ref<i1>
      cf.br ^join
    ^join:
      %en = simulation.context.storage %ctx[5] : !simulation.ref<i1>
      %take = simulation.ref.load %en : !simulation.ref<i1> -> i1
      cf.cond_br %take, ^use, ^done
    ^use:
      %payload = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<8>>
      %output = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<8>>
      %value = simulation.ref.load %payload : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      %sum = simulation.logic.binary add %value, %one : !simulation.logic<8>
      simulation.nba.enqueue %sum to %output : (!simulation.logic<8>, !simulation.ref<!simulation.logic<8>>) -> ()
      cf.br ^done
    ^done:
      %counter = simulation.context.storage %ctx[4] : !simulation.ref<!simulation.logic<8>>
      %old = simulation.ref.load %counter : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %counter_one = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      %next = simulation.logic.binary add %old, %counter_one : !simulation.logic<8>
      simulation.ref.store %next to %counter : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      cf.br ^wait
    }
  }
}
