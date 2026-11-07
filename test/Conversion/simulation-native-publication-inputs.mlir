// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --check-prefix=FANOUT < %t

// IEEE 1800-2023 4.3/4.6/9.4.2: the reread sees this activation's preceding
// store, so it creates no incoming-output feedback. Repeated stores still
// publish intermediate transitions: @writer is not repeatable, and changing
// an unused upper input bit must retain its original whole-byte wake.
// An old-output read used only by an overwritten intermediate publication is
// still feedback (4.3/4.6). Final-output dependencies alone cannot admit it.
// TRACE-DAG: talos eval dependency: owner={{[0-9]+}} {{.*}}body=writer.__talos_eval_body_0
// TRACE-DAG: talos eval boundary: owner={{[0-9]+}} {{.*}}body=old_output.__talos_eval_body_0
// FANOUT: llvm.mlir.global internal constant @__talos_aot_static_fanout_v1(
// FANOUT-SAME: [1 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,

!r = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @publication_inputs {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "writer"
    simulation.code_unit.decl 3 in 0 always hierarchy "observer"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "old_output"
    simulation.code_unit.decl 5 in 0 always hierarchy "old_observer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @old_output(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @old_observer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %middle = simulation.context.storage %ctx[1] : !r
      %output = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %middle : i8, !r
      %low = simulation.ref.extract %input from 0 : !r -> !simulation.ref<i4>
      %nibble = simulation.ref.load %low : !simulation.ref<i4> -> i4
      %value = arith.extui %nibble : i4 to i8
      simulation.ref.store %value to %middle : i8, !r
      %reread = simulation.ref.load %middle : !r -> i8
      simulation.ref.store %reread to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %middle = simulation.context.storage %ctx[1] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %middle : !r -> i8
      %format = simulation.bytes.constant "%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %value) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      simulation.suspend.change %middle to ^body : !r
    }
    simulation.func @old_output(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[3] : !r
      %middle = simulation.context.storage %ctx[4] : !r
      %output = simulation.context.storage %ctx[5] : !r
      cf.br ^body
    ^body:
      %old = simulation.ref.load %output : !r -> i8
      simulation.ref.store %old to %middle : i8, !r
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %middle : i8, !r
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
    simulation.func @old_observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %middle = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %middle : !r -> i8
      %format = simulation.bytes.constant "%0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %value) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      simulation.suspend.change %middle to ^body : !r
    }
  }
}
