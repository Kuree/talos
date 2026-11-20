// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir
// RUN: FileCheck %s --check-prefix=IR < %t.mlir

// The assertion canceller watches the ends of a packed value for a mismatch.
// Two whole-vector writes raise and clear both ends before it can resume.
// It must wake only on the later write that genuinely makes them different
// (1800-2023 4.6(b), 9.4.2, 16.12).
// A separate blocking write checks that the shared periodic clock captured
// a 73-bit unaligned range and a three-bit X range at slot entry (16.5.1).
// IR-DAG: llvm.mlir.constant(46116860184273879{{[0-9]+}} : i64)
// IR-DAG: llvm.call @talos_rt_v1_static_nba_commit_wide_ordered(
// IR-DAG: llvm.call @talos_rt_v1_eval_nba_reserve_records(
// IR-DAG: llvm.call @talos_rt_v1_scheduler_enter_sampled_periodic_aot(
// IR-DAG: llvm.func internal @__talos_sampled_plane_copy_v1(

!bit = !simulation.logic<1>
!clock = !simulation.ref<!bit>
!wide = !simulation.logic<65>
!wref = !simulation.ref<!wide>
!data = !simulation.logic<86>
!dref = !simulation.ref<!data>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, schedule.eval.runtime_calendar, native.closed_executable} {
  simulation.design @packed_update {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !wide design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !data design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "writer"
    simulation.code_unit.decl 4 in 0 fork hierarchy "edge"
    simulation.code_unit.decl 5 in 0 initial hierarchy "report"
    simulation.code_unit.decl 6 in 0 observer hierarchy "different"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clock = simulation.context.storage %ctx[0] : !clock
      %q = simulation.context.storage %ctx[1] : !wref
      %seen = simulation.context.storage %ctx[2] : !clock
      %no = simulation.logic.constant false, false : !bit
      %zero = simulation.logic.constant 0 : i65, 0 : i65 : !wide
      simulation.ref.store %no to %clock : !bit, !clock
      simulation.ref.store %no to %seen : !bit, !clock
      simulation.ref.store %zero to %q : !wide, !wref
      %data = simulation.context.storage %ctx[3] : !dref
      %initial = simulation.logic.constant 37778931862957161709576 : i86, 67699845898419233783545856 : i86 : !data
      simulation.ref.store %initial to %data : !data, !dref
      %a = simulation.spawn @clock(%ctx, %clock) : !simulation.context, !clock -> !simulation.process
      %b = simulation.spawn @writer(%ctx, %clock, %q) : !simulation.context, !clock, !wref -> !simulation.process
      %c = simulation.spawn @edge(%ctx, %q, %seen) : !simulation.context, !wref, !clock -> !simulation.process
      %d = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clock: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clock : !clock -> !bit
      %new = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %new to %clock : !bit, !clock
      cf.br ^wait
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clock: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clock to ^write {site = #schedule.continuation<id = 2>} : !clock
    ^write:
      %raised = simulation.logic.constant 18446744073709551617 : i65, 0 : i65 : !wide
      %zero = simulation.logic.constant 0 : i65, 0 : i65 : !wide
      simulation.nba.enqueue %raised to %q : (!wide, !wref) -> ()
      simulation.nba.enqueue %zero to %q : (!wide, !wref) -> ()
      cf.br ^wait
    }
    simulation.func private @different(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) -> i1 attributes {entry_kind = 14 : i32, code_unit_id = 6 : i64, internal, schedule.concurrent_cancel_observer, schedule.detached_controls, schedule.observer_four_state = false, schedule.observer_width = 1 : i32} {
      %low = simulation.ref.extract %q from 0 : !wref -> !clock
      %high = simulation.ref.extract %q from 64 : !wref -> !clock
      %a = simulation.ref.load %low : !clock -> !bit
      %b = simulation.ref.load %high : !clock -> !bit
      %equal = simulation.logic.compare case_eq %a, %b : (!bit, !bit) -> i1
      %yes = arith.constant true
      %different = arith.xori %equal, %yes : i1
      simulation.return %different : i1
    }
    simulation.func private @edge(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %seen: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, internal, schedule.concurrent_cancel, schedule.detached_controls, schedule.priority_signal_resume} {
      %no = arith.constant false
      %bound = simulation.observer.bind @different values(%q, %q : !wref, !wref) captures 1 : !simulation.observer<i1>
      simulation.suspend.observe %bound, %no conditions 0 edges [1] indices [-1] to ^hit {resume_region = 2 : i32, schedule.concurrent_cancel_level_true, site = #schedule.continuation<id = 3>} : !simulation.observer<i1>, i1
    ^hit:
      %yes = simulation.logic.constant true, false : !bit
      simulation.ref.store %yes to %seen : !bit, !clock
      simulation.return
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %delay = simulation.time.constant 6
      simulation.suspend.delay %delay to ^report {site = #schedule.continuation<id = 4>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^report:
      %seen = simulation.context.storage %ctx[2] : !clock
      %q = simulation.context.storage %ctx[1] : !wref
      %edge = simulation.ref.load %seen : !clock -> !bit
      %value = simulation.ref.load %q : !wref -> !wide
      %format = simulation.bytes.constant "seen=%b final=%017h"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%format, %edge, %value) newline = true radix = <hex> flags = [0, 0, 0] : !simulation.bytes, !bit, !wide
      %data = simulation.context.storage %ctx[3] : !dref
      %written = simulation.logic.constant -1 : i86, 0 : i86 : !data
      simulation.ref.store %written to %data : !data, !dref
      %field = simulation.ref.extract %data from 3 : !dref -> !simulation.ref<!simulation.logic<73>>
      %top = simulation.ref.extract %data from 83 : !dref -> !simulation.ref<!simulation.logic<3>>
      %pre = simulation.assert.sampled_read %ctx from %field : (!simulation.context, !simulation.ref<!simulation.logic<73>>) -> !simulation.logic<73>
      %tail = simulation.assert.sampled_read %ctx from %top : (!simulation.context, !simulation.ref<!simulation.logic<3>>) -> !simulation.logic<3>
      %sampleFmt = simulation.bytes.constant "sample=%019h tail=%b"
      simulation.display %ctx to %stdout(%sampleFmt, %pre, %tail) newline = true radix = <hex> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<73>, !simulation.logic<3>
      %one = simulation.logic.constant 1 : i65, 0 : i65 : !wide
      simulation.nba.enqueue %one to %q : (!wide, !wref) -> ()
      %later = simulation.time.constant 1
      simulation.suspend.delay %later to ^after {site = #schedule.continuation<id = 5>, timing = #schedule.timing_site<id = 2, kind = calendar>}
    ^after:
      %q2 = simulation.context.storage %ctx[1] : !wref
      %seen2 = simulation.context.storage %ctx[2] : !clock
      %actual = simulation.ref.load %q2 : !wref -> !wide
      %woken = simulation.ref.load %seen2 : !clock -> !bit
      %fmt = simulation.bytes.constant "seen=%b final=%017h"
      %out = arith.constant 1 : i32
      simulation.display %ctx to %out(%fmt, %woken, %actual) newline = true radix = <hex> flags = [0, 0, 0] : !simulation.bytes, !bit, !wide
      %ok = arith.constant 0 : i32
      simulation.finish %ctx, %ok
      simulation.return
    }
  }
}
