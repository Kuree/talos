// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir
// RUN: FileCheck %s --check-prefix=IR < %t.mlir

// Two plain unpacked elements share one whole-array NBA. The second write
// equal to CURRENT restores an earlier pending edge. A later X changes only
// the unknown plane. An equal capture with an empty FIFO has no effect
// (1800-2023 7.6, 4.6(b), 4.9.4, 9.4.2).
// IR: %[[V:[0-9]+]] = llvm.load {{.*}} : !llvm.ptr -> i1024
// IR-NEXT: %[[VD:[0-9]+]] = llvm.xor {{.*}}, %[[V]] : i1024
// IR: %[[X:[0-9]+]] = llvm.load {{.*}} : !llvm.ptr -> i1024
// IR-NEXT: %[[XD:[0-9]+]] = llvm.xor {{.*}}, %[[X]] : i1024
// IR-NEXT: llvm.or %[[VD]], %[[XD]] : i1024
// IR: llvm.call @talos_rt_v1_scheduler_generic_nba_pending(
// IR: llvm.call @talos_rt_v1_scheduler_nba(

!lane = !simulation.logic<512>
!a = !simulation.unpacked_array<1 : 0 x !lane>
!ref = !simulation.ref<!a>
!cell = !simulation.ref<!lane>
!one = !simulation.logic<1>
!bit = !simulation.ref<!one>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.closed_executable, schedule.native_scheduler = 3 : i32, schedule.force_generic_nba} {
  simulation.design @whole_array {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !a design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "writer"
    simulation.code_unit.decl 3 in 0 always hierarchy "edge"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !ref
      %e = simulation.spawn @edge(%ctx, %a) : !simulation.context, !ref -> !simulation.process
      %w = simulation.spawn @writer(%ctx, %a) : !simulation.context, !ref -> !simulation.process
      simulation.return
    }
    simulation.func private @edge(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %element = simulation.ref.subelement %a[[0]] : !ref -> !cell
      %bit = simulation.ref.extract %element from 0 : !cell -> !bit
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %bit to ^hit : !bit
    ^hit:
      %seen = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %old = simulation.ref.load %seen : !simulation.ref<i8> -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %old, %one : i8
      simulation.ref.store %next to %seen : i8, !simulation.ref<i8>
      cf.br ^wait
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %zero = simulation.logic.constant 0 : i512, 0 : i512 : !lane
      %one = simulation.logic.constant 1 : i512, 0 : i512 : !lane
      %x = simulation.logic.constant 0 : i512, 1 : i512 : !lane
      %base = simulation.aggregate.construct %zero, %zero : (!lane, !lane) -> !a
      %pulse = simulation.aggregate.construct %one, %zero : (!lane, !lane) -> !a
      %unknown = simulation.aggregate.construct %zero, %x : (!lane, !lane) -> !a
      %delay = simulation.time.constant 1
      simulation.nba.enqueue %base to %a : (!a, !ref) -> ()
      simulation.suspend.delay %delay to ^pulse
    ^pulse:
      simulation.nba.enqueue %base to %a : (!a, !ref) -> ()
      simulation.nba.enqueue %pulse to %a : (!a, !ref) -> ()
      simulation.nba.enqueue %base to %a : (!a, !ref) -> ()
      simulation.suspend.delay %delay to ^inspect
    ^inspect:
      %seen = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %count = simulation.ref.load %seen : !simulation.ref<i8> -> i8
      %last = simulation.ref.subelement %a[[1]] : !ref -> !cell
      %bit = simulation.ref.extract %last from 0 : !cell -> !bit
      %value = simulation.ref.load %bit : !bit -> !one
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "before %0d %b"
      simulation.display %ctx to %fd(%fmt, %count, %value) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, !one
      simulation.nba.enqueue %unknown to %a : (!a, !ref) -> ()
      simulation.suspend.delay %delay to ^finish
    ^finish:
      %tail = simulation.ref.load %bit : !bit -> !one
      %total = simulation.ref.load %seen : !simulation.ref<i8> -> i8
      %end = simulation.bytes.constant "after %0d %b"
      simulation.display %ctx to %fd(%end, %total, %tail) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, !one
      %exit = arith.constant 0 : i32
      simulation.finish %ctx, %exit
      simulation.return
    }
  }
}
