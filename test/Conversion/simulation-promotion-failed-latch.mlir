// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// A readiness scan that finds X/Z caches FAILED (2) in its owner's latch.
// Later queries return false without scanning until a publication touching
// the certificate (a recheck or an invalidation) resets the latch to UNKNOWN.
// A stale FAILED only keeps the four-state body, which is correct on any
// state (IEEE 1800-2023 6.3.1); the proven (1) path is unchanged.

// CHECK-LABEL: llvm.func @__talos_eval_kernel_promotion_scan_v1(
// CHECK: %[[FAILED:[0-9]+]] = llvm.mlir.constant(2 : i8) : i8
// CHECK-NEXT: %[[LATCHES:[0-9]+]] = llvm.mlir.addressof @__talos_eval_kernel_promotion_latched_v1
// CHECK-NEXT: %[[LATCH:[0-9]+]] = llvm.getelementptr %[[LATCHES]][%arg0]
// CHECK-NEXT: llvm.store %[[FAILED]], %[[LATCH]]
// CHECK-NEXT: %[[NO:[0-9]+]] = llvm.mlir.constant(false) : i1
// CHECK-NEXT: llvm.return %[[NO]] : i1
// A cached latch (KNOWN 1 or FAILED 2) answers with its low bit; only an
// UNKNOWN latch scans.
// CHECK-LABEL: llvm.func @__talos_eval_kernel_promotion_ready_v1(
// CHECK: %[[STATE:[0-9]+]] = llvm.load
// CHECK-NEXT: %[[ZERO:[0-9]+]] = llvm.mlir.constant(0 : i8) : i8
// CHECK-NEXT: %[[CACHED:[0-9]+]] = llvm.icmp "ne" %[[STATE]], %[[ZERO]] : i8
// CHECK-NEXT: llvm.cond_br %[[CACHED]], ^[[ANSWER:bb[0-9]+]], ^[[SCAN:bb[0-9]+]]
// CHECK-NEXT: ^[[ANSWER]]:
// CHECK-NEXT: %[[PROVEN:[0-9]+]] = llvm.trunc %[[STATE]] : i8 to i1
// CHECK-NEXT: llvm.return %[[PROVEN]] : i1
// CHECK-NEXT: ^[[SCAN]]:
// CHECK-NEXT: llvm.call @__talos_eval_kernel_promotion_scan_v1(%arg0)

!clk = !simulation.ref<i1>
!byte = !simulation.ref<!simulation.logic<8>>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @failed_latch {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.writer"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.reader"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !simulation.logic<8> design
    simulation.storage.decl 2 in 0 : !simulation.logic<8> design
    simulation.storage.decl 3 in 0 : !simulation.logic<8> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %s = simulation.context.storage %ctx[1] : !byte
      %d = simulation.context.storage %ctx[2] : !byte
      %n = simulation.context.storage %ctx[3] : !byte
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %x = simulation.logic.constant 1 : i8, 240 : i8 : !simulation.logic<8>
      simulation.ref.store %x to %s : !simulation.logic<8>, !byte
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %w = simulation.spawn @writer(%ctx, %clk, %s, %d) : !simulation.context, !clk, !byte, !byte -> !simulation.process
      %r = simulation.spawn @reader(%ctx, %d, %n) : !simulation.context, !byte, !byte -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %s: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %d: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %v = simulation.ref.load %s : !byte -> !simulation.logic<8>
      simulation.ref.store %v to %d {schedule.eval.nba_equivalent_store} : !simulation.logic<8>, !byte
      cf.br ^wait
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %n: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %d to ^body {site = #schedule.continuation<id = 3>} : !byte
    ^body:
      %v = simulation.ref.load %d : !byte -> !simulation.logic<8>
      simulation.ref.store %v to %n : !simulation.logic<8>, !byte
      cf.br ^wait
    }
  }
}
