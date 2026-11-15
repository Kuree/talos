// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-activation-regions{verify-prepared-views=true functions=producer,consumer order=true interleaving=true},test-talos-activation-regions{verify-prepared-views=true functions=feedback_producer,feedback_consumer order=true interleaving=true},test-talos-activation-regions{verify-prepared-views=true functions=unwatched_producer,unwatched_consumer order=true interleaving=true})' -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=FUSED

// Both processes unconditionally pulse the other's watched input, but the
// physical byte load only uses the lower nibble: an indexed lane proof
// removes the false value edge and keeps every intermediate store in source
// order (IEEE 1800-2023 4.6, 4.7). The clocked observer rules out the
// fallback that discards statement order. Two handoffs (producer body,
// consumer body and re-arm, producer re-arm) are necessary and sufficient.
// CHECK: interleaving order: acyclic refined=2 livelock-witness=1 preserved=n/a handoffs=2
// CHECK-NEXT: interleaving order: acyclic refined=2 livelock-witness=1 preserved=n/a handoffs=2
// CHECK-NEXT: region order: cyclic
// A genuinely used feedback lane stays cyclic: nothing is removed merely
// because both owners share an SCC.
// CHECK: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable
// CHECK-NEXT: interleaving order: cyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable
// CHECK-NEXT: region order: cyclic
// The upper bits pulse but the peer watches the lower nibble: no livelock.
// CHECK: interleaving order: acyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable
// CHECK-NEXT: interleaving order: acyclic refined=0 livelock-witness=0 preserved=1 handoffs=unavailable
// CHECK-NEXT: region order: acyclic
// FUSED-LABEL: simulation.design @lanes
// FUSED: simulation.func private @__talos_region_kernel_
// FUSED: %[[ZERO:.*]] = simulation.logic.constant 0 : i4, 0 : i4
// FUSED: %[[ONES:.*]] = simulation.logic.constant -1 : i4, 0 : i4
// FUSED: %[[X:.*]] = simulation.context.storage %arg0[0]
// FUSED: %[[LOW:.*]] = simulation.ref.extract %[[X]] from 0
// FUSED: %[[Y:.*]] = simulation.context.storage %arg0[1]
// FUSED-NEXT: simulation.ref.store %[[ZERO]] to %[[Y]]
// FUSED-NEXT: simulation.ref.store %[[ONES]] to %[[Y]]
// FUSED-NEXT: %[[BYTE:.*]] = simulation.ref.load %[[X]]
// FUSED-NEXT: %[[VALUE:.*]] = simulation.logic.extract %[[BYTE]] from 0
// FUSED-NEXT: simulation.ref.store %[[VALUE]] to %[[Y]]
// FUSED: %[[HIGH:.*]] = simulation.ref.extract %[[X]] from 4
// FUSED-NEXT: simulation.ref.store %[[ZERO]] to %[[HIGH]]
// FUSED-NEXT: simulation.ref.store %[[ONES]] to %[[HIGH]]
// FUSED-NEXT: simulation.ref.store %[[VALUE]] to %[[HIGH]]
// Only the external lower nibble remains in the common wait.
// FUSED: simulation.suspend.any %[[LOW]] edges [0] to
!byte = !simulation.logic<8>
!nib = !simulation.logic<4>
!bref = !simulation.ref<!byte>
!nref = !simulation.ref<!nib>
simulation.design @lanes {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !byte design
  simulation.storage.decl 1 in 0 : !nib design
  simulation.storage.decl 2 in 0 : i1 design
  simulation.storage.decl 3 in 0 : !nib design
  simulation.storage.decl 4 in 0 : !byte design
  simulation.storage.decl 5 in 0 : !nib design
  simulation.storage.decl 6 in 0 : !byte design
  simulation.storage.decl 7 in 0 : !byte design
  simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
  simulation.code_unit.decl 2 in 0 always_comb hierarchy "consumer"
  simulation.code_unit.decl 3 in 0 always hierarchy "sample"
  simulation.code_unit.decl 4 in 0 always_comb hierarchy "feedback.p"
  simulation.code_unit.decl 5 in 0 always_comb hierarchy "feedback.c"
  simulation.code_unit.decl 6 in 0 always_comb hierarchy "unwatched.p"
  simulation.code_unit.decl 7 in 0 always_comb hierarchy "unwatched.c"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
    simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @consumer(%ctx) : !simulation.context -> !simulation.process
    simulation.spawn @sample(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
    %x = simulation.context.storage %ctx[0] : !bref
    %y = simulation.context.storage %ctx[1] : !nref
    cf.br ^body
  ^body:
    %zero = simulation.logic.constant 0 : i4, 0 : i4 : !nib
    %ones = simulation.logic.constant 15 : i4, 0 : i4 : !nib
    simulation.ref.store %zero to %y : !nib, !nref
    simulation.ref.store %ones to %y : !nib, !nref
    %v = simulation.ref.load %x : !bref -> !byte
    %low = simulation.logic.extract %v from 0 : !byte -> !nib
    simulation.ref.store %low to %y : !nib, !nref
    simulation.suspend.change %x to ^body : !bref
  }
  simulation.func @consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
    %x = simulation.context.storage %ctx[0] : !bref
    %high = simulation.ref.extract %x from 4 : !bref -> !nref
    %y = simulation.context.storage %ctx[1] : !nref
    cf.br ^body
  ^body:
    %zero = simulation.logic.constant 0 : i4, 0 : i4 : !nib
    %ones = simulation.logic.constant 15 : i4, 0 : i4 : !nib
    simulation.ref.store %zero to %high : !nib, !nref
    simulation.ref.store %ones to %high : !nib, !nref
    %v = simulation.ref.load %y : !nref -> !nib
    simulation.ref.store %v to %high : !nib, !nref
    simulation.suspend.change %y to ^body : !nref
  }
  simulation.func @sample(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
    %clk = simulation.context.storage %ctx[2] : !simulation.ref<i1>
    %y = simulation.context.storage %ctx[1] : !nref
    %saved = simulation.context.storage %ctx[3] : !nref
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body : !simulation.ref<i1>
  ^body:
    %v = simulation.ref.load %y : !nref -> !nib
    simulation.nba.enqueue %v to %saved : (!nib, !nref) -> ()
    cf.br ^wait
  }
  simulation.func @feedback_producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
    %x = simulation.context.storage %ctx[4] : !bref
    %y = simulation.context.storage %ctx[5] : !nref
    cf.br ^body
  ^body:
    %v = simulation.ref.load %x : !bref -> !byte
    %high = simulation.logic.extract %v from 4 : !byte -> !nib
    simulation.ref.store %high to %y : !nib, !nref
    simulation.suspend.change %x to ^body : !bref
  }
  simulation.func @feedback_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
    %x = simulation.context.storage %ctx[4] : !bref
    %high = simulation.ref.extract %x from 4 : !bref -> !nref
    %y = simulation.context.storage %ctx[5] : !nref
    cf.br ^body
  ^body:
    %v = simulation.ref.load %y : !nref -> !nib
    simulation.ref.store %v to %high : !nib, !nref
    simulation.suspend.change %y to ^body : !nref
  }
  simulation.func @unwatched_producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
    %x = simulation.context.storage %ctx[6] : !bref
    %low = simulation.ref.extract %x from 0 : !bref -> !nref
    %y = simulation.context.storage %ctx[7] : !bref
    cf.br ^body
  ^body:
    %zero = simulation.logic.constant 0 : i8, 0 : i8 : !byte
    %lower = simulation.logic.constant 15 : i8, 0 : i8 : !byte
    simulation.ref.store %zero to %y : !byte, !bref
    simulation.ref.store %lower to %y : !byte, !bref
    simulation.suspend.change %low to ^body : !nref
  }
  simulation.func @unwatched_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
    %x = simulation.context.storage %ctx[6] : !bref
    %y = simulation.context.storage %ctx[7] : !bref
    %low = simulation.ref.extract %y from 0 : !bref -> !nref
    cf.br ^body
  ^body:
    %zero = simulation.logic.constant 0 : i8, 0 : i8 : !byte
    %upper = simulation.logic.constant 240 : i8, 0 : i8 : !byte
    simulation.ref.store %zero to %x : !byte, !bref
    simulation.ref.store %upper to %x : !byte, !bref
    simulation.suspend.change %low to ^body : !nref
  }
}
