// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep))' -o %t.plan
// RUN: FileCheck %s --check-prefix=SOURCE < %t.plan
// RUN: talos-opt %t.plan '--test-talos-set-module-attributes=attrs="{schedule.force_generic_nba}"' --encode-talos-sim-to-bytecode='vpi=off' --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=QUEUE
// RUN: talos-opt %t.plan '--test-talos-set-module-attributes=attrs="{schedule.force_generic_nba, native.two_state}"' --encode-talos-sim-to-bytecode='vpi=off' --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=QUEUE

// A blocking store drives only the high half of a packed pipeline. A hold
// on the low half can disappear if nothing is pending. A hold on the high
// half must still undo the later blocking store. A dynamically selected
// writer may overlap any lane of its root (IEEE 1800-2023 4.6, 10.4.2).
// SOURCE: schedule.nba.hold_ranges = array<i64: 0, 0, 3, 3, 0, 96>
// SOURCE-SAME: schedule.nba.immediate_writers = array<i64: 0, 1, 3>
// QUEUE-LABEL: llvm.func @writer.__talos_coro_ramp(
// QUEUE: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// QUEUE: llvm.call @talos_rt_v1_scheduler_nba_scalar(
// QUEUE-NOT: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// QUEUE: llvm.call @talos_rt_v1_scheduler_nba_scalar(
// QUEUE-NOT: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// QUEUE: llvm.call @talos_rt_v1_scheduler_nba_scalar(
// QUEUE-NOT: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// QUEUE: llvm.icmp "ne" {{.*}} : i96
// QUEUE: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// QUEUE: llvm.call @talos_rt_v1_scheduler_nba(
// QUEUE: llvm.return

!word = !simulation.logic<6>
!lane = !simulation.logic<3>
!wordref = !simulation.ref<!word>
!laneref = !simulation.ref<!lane>
!wide = !simulation.logic<97>
!payload = !simulation.logic<96>
!wideref = !simulation.ref<!wide>
!payloadref = !simulation.ref<!payload>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @pipeline {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !word design
    simulation.storage.decl 1 in 0 : !word design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : !wide design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "pipeline.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "pipeline.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %word = simulation.context.storage %ctx[0] : !wordref
      %low = simulation.ref.extract %word from 0 : !wordref -> !laneref
      %high = simulation.ref.extract %word from 3 : !wordref -> !laneref
      %zero = simulation.logic.constant 0 : i3, 0 : i3 : !lane
      %one = simulation.logic.constant 1 : i3, 0 : i3 : !lane
      simulation.nba.enqueue %zero to %low : (!lane, !laneref) -> ()
      simulation.nba.enqueue %zero to %high : (!lane, !laneref) -> ()
      simulation.ref.store %one to %high : !lane, !laneref
      %dynamic = simulation.context.storage %ctx[1] : !wordref
      %input = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %index = simulation.ref.load %input : !simulation.ref<i8> -> i8
      %fixed = simulation.ref.extract %dynamic from 0 : !wordref -> !laneref
      %selected = simulation.ref.dyn_extract %dynamic from %index : (!wordref, i8) -> !laneref
      simulation.nba.enqueue %zero to %fixed : (!lane, !laneref) -> ()
      simulation.ref.store %one to %selected : !lane, !laneref
      %wide = simulation.context.storage %ctx[3] : !wideref
      %payload = simulation.ref.extract %wide from 0 : !wideref -> !payloadref
      %top = simulation.ref.extract %wide from 96 : !wideref -> !simulation.ref<!simulation.logic<1>>
      %wideZero = simulation.logic.constant 0 : i96, 0 : i96 : !payload
      %bit = simulation.logic.constant true, false : !simulation.logic<1>
      simulation.nba.enqueue %wideZero to %payload : (!payload, !payloadref) -> ()
      simulation.ref.store %bit to %top : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^check
    ^check:
      %value = simulation.ref.load %word : !wordref -> !word
      %channel = arith.constant 1 : i32
      %format = simulation.bytes.constant "%h"
      simulation.display %ctx to %channel(%format, %value) newline = true radix = <hex> flags = [0, 0] : !simulation.bytes, !word
      simulation.return
    }
  }
}
