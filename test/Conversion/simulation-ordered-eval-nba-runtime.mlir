// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off})' -o %t.scheduled.mlir
// RUN: talos-opt %t.scheduled.mlir --convert-talos-sim-processes-to-llvm-coroutines -o %t.plan.mlir
// RUN: FileCheck %s --check-prefix=PLAN < %t.plan.mlir
// RUN: FileCheck %s --check-prefix=COLD < %t.plan.mlir
// RUN: talos-opt %t.scheduled.mlir '--test-talos-set-module-attributes=attrs="{schedule.force_generic_nba, native.closed_executable}"' --convert-talos-sim-processes-to-llvm-coroutines --materialize-runtime-byte-globals -o %t.generic.mlir
// RUN: FileCheck %s --check-prefix=GENERIC --implicit-check-not=__talos_eval_ordered_nba_queue_v1 --implicit-check-not=__talos_aot_nba_accumulator_ --implicit-check-not='llvm.call @talos_rt_v1_scheduler_generic_nba_pending' < %t.generic.mlir

// Growing the queue is the cold arm of a capacity test, so its runtime
// entries are declared cold.
// COLD: llvm.func @talos_rt_v1_eval_nba_reserve_records(!llvm.ptr, !llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<eval_nba_reserve_records>, passthrough = ["cold"]}
// COLD-NEXT: llvm.func @talos_rt_v1_eval_nba_reserve(!llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<eval_nba_reserve>, passthrough = ["cold"]}

// The writer runs twice before the NBA barrier: src=1 stages one, then a
// different actor resets src and stages zero at the SAME semantic site.
// The final value is zero, but a posedge observer must still run (LRM 4.6).
// PLAN: llvm.mlir.global internal @__talos_eval_ordered_nba_queue_v1
// Each same-site enqueue appends a new ordered entry, growing the queue
// through the runtime when full, instead of overwriting one pending slot.
// PLAN-LABEL: llvm.func @writer.__talos_eval_body_0(
// PLAN: %[[QUEUE:.*]] = llvm.mlir.addressof @__talos_eval_ordered_nba_queue_v1
// PLAN-NEXT: %[[COUNT_PTR:.*]] = llvm.getelementptr %[[QUEUE]][0, 1]
// PLAN-NEXT: %[[COUNT:.*]] = llvm.load %[[COUNT_PTR]]
// PLAN: llvm.call @talos_rt_v1_eval_nba_reserve(
// PLAN: llvm.getelementptr %{{.*}}[%{{.*}}] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<4 x i64>
// PLAN: %[[NEXT:.*]] = llvm.add %[[COUNT]], %{{.*}} : i32
// PLAN: llvm.store %[[NEXT]], %{{.*}} : i32, !llvm.ptr
// PLAN-LABEL: llvm.func @__talos_eval_dispatch_v1

// Forcing the generic queue keeps the generated writer and dispatcher.
// Each activation enqueues its captured value through the ordinary NBA ABI.
// Every call in the writer is one the catalog marks QueueStable (the queue
// query and the scalar capture), so the queue's words are bound once on entry
// and each query reads them in place of a runtime call (1800-2023 4.6(b),
// 10.4.2).
// GENERIC-LABEL: llvm.func @writer.__talos_eval_body_0(
// GENERIC: %[[CONTEXT:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// GENERIC-NEXT: %[[ROOT:.*]] = llvm.mlir.constant(4 : i32) : i32
// GENERIC-NEXT: %[[WORDS:.*]] = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%[[CONTEXT]], %[[ROOT]])
// GENERIC: llvm.load %[[WORDS]]
// GENERIC: llvm.call @talos_rt_v1_scheduler_nba_scalar(
// GENERIC-LABEL: llvm.func @__talos_eval_dispatch_v1(

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
!wide = !simulation.logic<65>
!wref = !simulation.ref<!wide>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32} {
  simulation.design @ordered {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !wide design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "ordered.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "ordered.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "ordered.forward"
    simulation.code_unit.decl 4 in 0 always hierarchy "ordered.writer"
    simulation.code_unit.decl 5 in 0 always hierarchy "ordered.reset"
    simulation.code_unit.decl 6 in 0 always hierarchy "ordered.edge"
    simulation.code_unit.decl 7 in 0 initial hierarchy "ordered.check"
    simulation.code_unit.decl 8 in 0 initial hierarchy "ordered.peek"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %src = simulation.context.storage %ctx[1] : !ref
      %kick = simulation.context.storage %ctx[2] : !ref
      %data = simulation.context.storage %ctx[3] : !wref
      %seen = simulation.context.storage %ctx[4] : !ref
      %zero = simulation.logic.constant false, false : !bit
      %zeros = simulation.logic.constant 0 : i65, 0 : i65 : !wide
      simulation.ref.store %zero to %clk : !bit, !ref
      simulation.ref.store %zero to %src : !bit, !ref
      simulation.ref.store %zero to %kick : !bit, !ref
      simulation.ref.store %zeros to %data : !wide, !wref
      simulation.ref.store %zero to %seen : !bit, !ref
      %a = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %b = simulation.spawn @forward(%ctx, %clk, %src) : !simulation.context, !ref, !ref -> !simulation.process
      %c = simulation.spawn @writer(%ctx, %src, %kick, %data) : !simulation.context, !ref, !ref, !wref -> !simulation.process
      %d = simulation.spawn @reset(%ctx, %kick, %src) : !simulation.context, !ref, !ref -> !simulation.process
      %e = simulation.spawn @edge(%ctx, %data, %seen) : !simulation.context, !wref, !ref -> !simulation.process
      %f = simulation.spawn @check(%ctx, %data, %seen) : !simulation.context, !wref, !ref -> !simulation.process
      %g = simulation.spawn @peek(%ctx, %clk, %data, %seen) : !simulation.context, !ref, !wref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> !bit
      %new = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %new to %clk : !bit, !ref
      cf.br ^wait
    }
    simulation.func @forward(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^copy {site = #schedule.continuation<id = 2>} : !ref
    ^copy:
      %value = simulation.ref.load %clk : !ref -> !bit
      simulation.ref.store %value to %src : !bit, !ref
      cf.br ^wait
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %kick: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %src to ^write {site = #schedule.continuation<id = 3>} : !ref
    ^write:
      %value = simulation.ref.load %src : !ref -> !bit
      %target = simulation.ref.extract %data from 0 : !wref -> !ref
      simulation.nba.enqueue %value to %target : (!bit, !ref) -> ()
      simulation.ref.store %value to %kick : !bit, !ref
      cf.br ^wait
    }
    simulation.func @reset(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %kick: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %kick edges [1] to ^reset {site = #schedule.continuation<id = 4>} : !ref
    ^reset:
      %zero = simulation.logic.constant false, false : !bit
      simulation.ref.store %zero to %src : !bit, !ref
      cf.br ^wait
    }
    simulation.func @edge(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %data edges [1] to ^edge {site = #schedule.continuation<id = 5>} : !wref
    ^edge:
      %one = simulation.logic.constant true, false : !bit
      simulation.ref.store %one to %seen : !bit, !ref
      cf.br ^wait
    }
    // The edge wakes an ordinary testbench process that resumes again at
    // #0. It must still see pre-NBA storage and the unwoken edge observer.
    simulation.func @peek(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 8 : i64} {
      simulation.suspend.edge posedge %clk to ^active {site = #schedule.continuation<id = 7>} : !ref
    ^active:
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^inactive {site = #schedule.continuation<id = 8>, timing = #schedule.timing_site<id = 2, kind = calendar>}
    ^inactive:
      %lo = simulation.ref.extract %data from 0 : !wref -> !ref
      %value = simulation.ref.load %lo : !ref -> !bit
      %edge = simulation.ref.load %seen : !ref -> !bit
      %fmt = simulation.bytes.constant "inactive=%b edge=%b"
      %fd = arith.constant 1 : i32
      simulation.display %ctx to %fd(%fmt, %value, %edge) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !bit, !bit
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^check {site = #schedule.continuation<id = 6>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^check:
      %value = simulation.ref.load %data : !wref -> !wide
      %edge = simulation.ref.load %seen : !ref -> !bit
      %format = simulation.bytes.constant "%017h %b"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%format, %value, %edge) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !wide, !bit
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
