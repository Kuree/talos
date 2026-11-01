// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s < %t.mlir

// Every entry path of an owner selects its value domain through one query. A
// ranked member that is a fused clocked kernel gets the retry state its dispatch
// entry has; any other member asks for the certificate itself. Choosing the
// four-state body is always correct (IEEE 1800-2023 6.3.1).
// CHECK: llvm.mlir.global internal @__talos_eval_kernel_retry_[[KERNEL:[0-9]+]]_v1(0 : i8)
// CHECK-LABEL: llvm.func @__talos_eval_ranked_group_0(
// CHECK: llvm.mlir.addressof @__talos_eval_kernel_retry_[[KERNEL]]_v1
// CHECK-NEXT: llvm.call @__talos_eval_clocked_kernel_ready_v1(
// CHECK: llvm.call @__talos_eval_kernel_promotion_ready_v1(

!clock = !simulation.ref<i1>
!word = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @ranked_retry {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock0"
    simulation.code_unit.decl 4 in 0 always hierarchy "rise_a"
    simulation.code_unit.decl 5 in 0 always hierarchy "rise_b"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clock
      %other = simulation.context.storage %ctx[1] : !clock
      %c0 = simulation.spawn @clock0(%ctx, %clk) : !simulation.context, !clock -> !simulation.process
      %kernel = simulation.spawn @__talos_clocked_7_1_0(%ctx, %clk, %other) : !simulation.context, !clock, !clock -> !simulation.process
      %plain = simulation.spawn @rise_b(%ctx, %clk, %other) : !simulation.context, !clock, !clock -> !simulation.process
      simulation.return
    }
    simulation.func @clock0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      %old = simulation.ref.load %clk : !clock -> i1
      %one = arith.constant true
      %next = arith.xori %old, %one : i1
      simulation.ref.store %next to %clk : i1, !clock
      cf.br ^wait
    }
    simulation.func @__talos_clocked_7_1_0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %other: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !clock
    ^body:
      %out = simulation.context.storage %ctx[2] : !word
      %old = simulation.ref.load %out : !word -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.nba.enqueue %next to %out : (i8, !word) -> ()
      cf.br ^wait
    }
    simulation.func @rise_b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %other: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !clock
    ^body:
      %out = simulation.context.storage %ctx[3] : !word
      %old = simulation.ref.load %out : !word -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      %temp = simulation.context.storage %ctx[4] : !word
      simulation.ref.store %next to %temp : i8, !word
      %reload = simulation.ref.load %temp : !word -> i8
      simulation.nba.enqueue %reload to %out : (i8, !word) -> ()
      cf.br ^wait
    }
  }
}
