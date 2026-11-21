// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=STORES < %t.mlir

// A clean direct 4-state store with a waiter tests old against new once, over
// both planes, before it writes anything. Only a change stores the value and
// X/Z planes, publishes the X/Z change to the two-state proofs and wakes the
// reader. IEEE 1800-2023 4.3: only a change in state of a variable is an
// update event, and any algorithm with the reference algorithm's visible
// effect is allowed; writing the value already held changes no state and
// wakes nothing (9.4.2: implicit events are value changes, x->x and z->z are
// no edge). The state is 4-valued (6.3.1), so 0<->x and x<->z changes still
// store and reach the transition, which applies the edge rules of Table 9-2.

// CHECK-LABEL: llvm.func @writer.__talos_eval_body_0(
// CHECK: %[[HELD:[0-9]+]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1
// CHECK-NOT: llvm.store
// CHECK: %[[SV:[0-9]+]] = llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NOT: llvm.store
// CHECK: %[[SU:[0-9]+]] = llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NOT: llvm.store
// Bind both deltas at their use: either XOR may be constructed first.
// The separate STORES check forbids writes throughout this DAG, too.
// CHECK-DAG: %[[CHANGE:[0-9]+]] = llvm.or %[[DV:[0-9]+]], %[[DU:[0-9]+]] : i64
// CHECK-DAG: %[[DV]] = llvm.xor %{{[0-9]+}}, %{{[0-9]+}} : i64
// CHECK-DAG: %[[DU]] = llvm.xor %{{[0-9]+}}, %{{[0-9]+}} : i64
// CHECK-NOT: llvm.store
// CHECK: %[[SAME:[0-9]+]] = llvm.icmp "eq" %[[CHANGE]], %{{[0-9]+}} : i64
// CHECK-NEXT: llvm.cond_br %[[SAME]], ^[[DONE:bb[0-9]+]], ^[[STORE:bb[0-9]+]]
// CHECK-NEXT: ^[[STORE]]:
// CHECK: llvm.mlir.addressof @__talos_state_value
// CHECK: llvm.store %[[SV]], %{{[0-9]+}} {alignment = 1 : i64} : i8, !llvm.ptr
// CHECK: llvm.mlir.addressof @__talos_state_unknown
// CHECK: llvm.store %[[SU]], %{{[0-9]+}} {alignment = 1 : i64} : i8, !llvm.ptr
// CHECK: llvm.call preserve_mostcc @__talos_eval_promotion_publish_window_v1
// CHECK: llvm.store %{{[0-9]+}}, %[[HELD]]
// CHECK: ^[[DONE]]:
// The two-state copy compares the value plane only and never stores X/Z.
// CHECK-LABEL: llvm.func @writer.__talos_eval_body_0.__talos_two_state_0(
// CHECK-NOT: llvm.store
// CHECK: %[[SAME2:[0-9]+]] = llvm.icmp "eq"
// CHECK-NEXT: llvm.cond_br %[[SAME2]], ^[[DONE2:bb[0-9]+]], ^[[STORE2:bb[0-9]+]]
// CHECK-NEXT: ^[[STORE2]]:
// CHECK-NOT: @__talos_state_unknown
// CHECK: llvm.store %{{[0-9]+}}, %{{[0-9]+}} {alignment = 1 : i64} : i8, !llvm.ptr
// CHECK-NOT: @__talos_state_unknown
// CHECK: ^[[DONE2]]:

// STORES-LABEL: llvm.func @writer.__talos_eval_body_0(
// STORES-NOT: llvm.store
// STORES: llvm.cond_br
// STORES-LABEL: llvm.func @writer.__talos_eval_body_0.__talos_two_state_0(
// STORES-NOT: llvm.store
// STORES: llvm.cond_br

!clk = !simulation.ref<i1>
!byte = !simulation.ref<!simulation.logic<8>>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @change_first {
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
