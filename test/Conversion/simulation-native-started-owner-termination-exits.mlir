// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=read},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=read},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --implicit-check-not='@inverted.__talos_start(' --implicit-check-not='@mixed.__talos_start(' < %t.mlir

// A process with a single signal wait can still return while simulation is
// running. Only the true edge of a termination poll permits startup admission.
// The inverted actor returns when the latch is clear. The mixed actor's return
// has two predecessors, one guarded by termination and one by ordinary data.
// TRACE: talos started owners: admitted=1 time_zero=0 {{.*}}wait=3
// CHECK: llvm.mlir.global internal constant @guarded.__talos_start(

!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {
    llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
    llvm.target_triple = "x86_64-unknown-linux-gnu",
    schedule.native_scheduler = 3 : i32, native.debug_timing, native.readable_eval_state, native.closed_executable} {
  simulation.design @guard_exits {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "guarded"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "inverted"
    simulation.code_unit.decl 5 in 0 always_ff hierarchy "mixed"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %d = simulation.context.storage %ctx[1] : !vref
      %q = simulation.context.storage %ctx[2] : !vref
      %inv = simulation.context.storage %ctx[3] : !vref
      %mix = simulation.context.storage %ctx[4] : !vref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @guarded(%ctx, %clk, %d, %q) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %pi = simulation.spawn @inverted(%ctx, %clk, %d, %inv) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %pm = simulation.spawn @mixed(%ctx, %clk, %d, %mix) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !ref
      cf.br ^wait
    }
    simulation.func @guarded(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64},
        %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64},
        %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64})
        attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      %stop = simulation.termination.requested %ctx
      cf.cond_br %stop, ^done, ^wait
    ^done:
      simulation.return
    }
    simulation.func @inverted(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64},
        %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64},
        %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64})
        attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 3>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      %stop = simulation.termination.requested %ctx
      cf.cond_br %stop, ^wait, ^done
    ^done:
      simulation.return
    }
    simulation.func @mixed(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64},
        %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64},
        %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64})
        attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 4>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      %stop = simulation.termination.requested %ctx
      cf.cond_br %stop, ^done, ^check
    ^check:
      %z = arith.constant 0 : i8
      %exit = arith.cmpi eq, %v, %z : i8
      cf.cond_br %exit, ^done, ^wait
    ^done:
      simulation.return
    }
  }
}
