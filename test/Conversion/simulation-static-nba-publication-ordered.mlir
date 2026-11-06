// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.guards.mlir
// RUN: FileCheck %s --check-prefix=GUARD < %t.guards.mlir && FileCheck %s --check-prefix=BODY < %t.guards.mlir
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.eval.runtime_calendar}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir 2> %t.plan
// RUN: FileCheck %s --check-prefix=REJECT < %t.plan && FileCheck %s --check-prefix=REJECTIR --implicit-check-not='llvm.call @__talos_eval_static_nba_publication' < %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// Ordered captures require the full commit. The static certificate guards both
// the queue count and its latched error, and contains no record dispatch.
// A shared runtime calendar rejects the entire static schedule. Its original
// commit route must preserve the 0->1->0 event even though the final value is 0
// (IEEE 1800-2023 4.6, 4.9.4, 9.4.2, 10.4.2).
// REJECT: talos eval static NBA publication: scalar=0 slot-roots=0
// REJECTIR-LABEL: llvm.func internal @__talos_eval_dispatch_v1.__talos_pending(
// REJECTIR: llvm.call @__talos_aot_runtime_nba_commit_v1.__talos_pending
// REJECTIR-LABEL: llvm.func @__talos_eval_four_state_nba_handoff_v1(
// REJECTIR: llvm.call @__talos_aot_static_nba_commit_v1
// OUTPUT: {{^}}1 16 16 16 1 5{{$}}
// BODY-LABEL: llvm.func internal @__talos_eval_static_nba_publication_v1(
// BODY-NOT: @__talos_aot_static_nba_commit
// BODY-NOT: @talos_rt_v1_static_nba_commit
// BODY-NOT: @__talos_eval_nba_commit_
// BODY-NOT: llvm.switch
// BODY: {{^  }}}
// GUARD-LABEL: llvm.func internal @__talos_eval_static_nba_publication_guard_v1(
// GUARD-NOT: llvm.switch
// GUARD-NOT: @__talos_eval_nba_commit_
// GUARD: llvm.mlir.addressof @__talos_eval_ordered_nba_queue_v1
// GUARD: llvm.getelementptr {{.*}}[0, 1]
// GUARD: llvm.mlir.addressof @__talos_eval_ordered_nba_queue_v1
// GUARD: llvm.getelementptr {{.*}}[0, 3]
// GUARD: llvm.icmp "eq"
// GUARD-NOT: llvm.switch
// GUARD-NOT: @__talos_eval_nba_commit_
// GUARD: llvm.return

!bit = !simulation.logic<1>
!clock = !simulation.ref<!bit>
!word = !simulation.logic<17>
!ref = !simulation.ref<!word>
!packed = !simulation.logic<19>
!pref = !simulation.ref<!packed>
!wide = !simulation.logic<130>
!wref = !simulation.ref<!wide>
!pulse = !simulation.logic<65>
!uref = !simulation.ref<!pulse>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @publication {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !packed design
    simulation.storage.decl 2 in 0 : !word design
    simulation.storage.decl 3 in 0 : !word design
    simulation.storage.decl 4 in 0 : !word design
    simulation.storage.decl 5 in 0 : !wide design
    simulation.storage.decl 6 in 0 : !pulse design
    simulation.storage.decl 7 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "step"
    simulation.code_unit.decl 4 in 0 always hierarchy "wide"
    simulation.code_unit.decl 5 in 0 always hierarchy "pulse"
    simulation.code_unit.decl 6 in 0 always hierarchy "edge"
    simulation.code_unit.decl 7 in 0 initial hierarchy "sample"
    simulation.code_unit.decl 8 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clock
      %q = simulation.context.storage %ctx[1] : !pref
      %mirror = simulation.context.storage %ctx[2] : !ref
      %active = simulation.context.storage %ctx[3] : !ref
      %inactive = simulation.context.storage %ctx[4] : !ref
      %wide = simulation.context.storage %ctx[5] : !wref
      %pulse = simulation.context.storage %ctx[6] : !uref
      %edges = simulation.context.storage %ctx[7] : !int
      %false = simulation.logic.constant false, false : !bit
      %zero = arith.constant 0 : i32
      %q0 = simulation.logic.constant 262145 : i19, 0 : i19 : !packed
      %u0 = simulation.logic.constant 0 : i65, 0 : i65 : !pulse
      %w0 = simulation.logic.constant 0 : i130, 0 : i130 : !wide
      simulation.ref.store %false to %clk : !bit, !clock
      simulation.ref.store %q0 to %q : !packed, !pref
      simulation.ref.store %w0 to %wide : !wide, !wref
      simulation.ref.store %u0 to %pulse : !pulse, !uref
      simulation.ref.store %zero to %edges : i32, !int
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clock -> !simulation.process
      %p1 = simulation.spawn @step(%ctx, %clk, %q, %mirror) : !simulation.context, !clock, !pref, !ref -> !simulation.process
      %p2 = simulation.spawn @wide(%ctx, %clk, %wide) : !simulation.context, !clock, !wref -> !simulation.process
      %p3 = simulation.spawn @pulse(%ctx, %clk, %q, %pulse) : !simulation.context, !clock, !pref, !uref -> !simulation.process
      %p4 = simulation.spawn @edge(%ctx, %pulse, %edges) : !simulation.context, !uref, !int -> !simulation.process
      %p5 = simulation.spawn @sample(%ctx, %clk, %q, %active, %inactive) : !simulation.context, !clock, !pref, !ref, !ref -> !simulation.process
      %p6 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clock -> !bit
      %next = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %next to %clk : !bit, !clock
      cf.br ^wait
    }
    simulation.func @step(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !pref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %mirror: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 2>} : !clock
    ^write:
      %target = simulation.ref.extract %q from 1 : !pref -> !ref
      %old = simulation.ref.load %target : !ref -> !word
      %one = simulation.logic.constant 1 : i17, 0 : i17 : !word
      %first = simulation.logic.binary add %old, %one : !word
      %second = simulation.logic.binary add %first, %one : !word
      simulation.nba.enqueue %first to %target : (!word, !ref) -> ()
      simulation.nba.enqueue %second to %target : (!word, !ref) -> ()
      %incoming = simulation.ref.load %target : !ref -> !word
      simulation.nba.enqueue %incoming to %mirror : (!word, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @wide(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !wref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 3>} : !clock
    ^write:
      %clock_logic = simulation.ref.load %clk : !clock -> !bit
      %clock = simulation.logic.to_bits %clock_logic : !bit -> i1
      %x = simulation.logic.constant 0 : i130, -1 : i130 : !wide
      %z = simulation.logic.constant -1 : i130, -1 : i130 : !wide
      %value = arith.select %clock, %x, %z : !wide
      simulation.nba.enqueue %value to %q : (!wide, !wref) -> ()
      cf.br ^wait
    }
    simulation.func @pulse(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !pref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %u: !uref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^write {site = #schedule.continuation<id = 4>} : !clock
    ^write:
      %target = simulation.ref.extract %u from 0 : !uref -> !simulation.ref<!bit>
      %one = simulation.ref.load %clk : !clock -> !bit
      %zero = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %one to %target : (!bit, !simulation.ref<!bit>) -> ()
      simulation.nba.enqueue %zero to %target : (!bit, !simulation.ref<!bit>) -> ()
      cf.br ^wait
    }
    simulation.func @edge(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %u: !uref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %edges: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %u edges [1] to ^count {site = #schedule.continuation<id = 5>} : !uref
    ^count:
      %old = simulation.ref.load %edges : !int -> i32
      %one = arith.constant 1 : i32
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %edges : i32, !int
      cf.br ^wait
    }
    simulation.func @sample(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !pref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %active: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %inactive: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %clk to ^active {site = #schedule.continuation<id = 6>} : !clock
    ^active:
      %target = simulation.ref.extract %q from 1 : !pref -> !ref
      %old = simulation.ref.load %target : !ref -> !word
      simulation.ref.store %old to %active : !word, !ref
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^inactive {site = #schedule.continuation<id = 7>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^inactive:
      %after = simulation.ref.load %target : !ref -> !word
      simulation.ref.store %after to %inactive : !word, !ref
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 8 : i64} {
      %delay = simulation.time.constant 46
      simulation.suspend.delay %delay to ^report {site = #schedule.continuation<id = 8>, timing = #schedule.timing_site<id = 2, kind = calendar>}
    ^report:
      %q = simulation.context.storage %ctx[1] : !pref
      %mirror = simulation.context.storage %ctx[2] : !ref
      %active = simulation.context.storage %ctx[3] : !ref
      %inactive = simulation.context.storage %ctx[4] : !ref
      %wide = simulation.context.storage %ctx[5] : !wref
      %edges = simulation.context.storage %ctx[7] : !int
      %qv = simulation.ref.load %q : !pref -> !packed
      %expected = simulation.logic.constant 262181 : i19, 0 : i19 : !packed
      %correct = simulation.logic.compare case_eq %qv, %expected : (!packed, !packed) -> i1
      %m = simulation.ref.load %mirror : !ref -> !word
      %a = simulation.ref.load %active : !ref -> !word
      %i = simulation.ref.load %inactive : !ref -> !word
      %w = simulation.ref.load %wide : !wref -> !wide
      %x = simulation.logic.constant 0 : i130, -1 : i130 : !wide
      %unknown = simulation.logic.compare case_eq %w, %x : (!wide, !wide) -> i1
      %n = simulation.ref.load %edges : !int -> i32
      %format = simulation.bytes.constant "%b %0d %0d %0d %b %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%format, %correct, %m, %a, %i, %unknown, %n) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0, 0] : !simulation.bytes, i1, !word, !word, !word, i1, i32
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
