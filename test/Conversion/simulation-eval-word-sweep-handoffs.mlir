// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.priority erase},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.sparse.mlir 2> %t.sparse.trace
// RUN: FileCheck %s --check-prefix=SPARSE < %t.sparse.mlir
// RUN: FileCheck %s --check-prefix=SPARSE-PLAN < %t.sparse.trace

// The counter owners cannot fuse because they may terminate. The pure `aaa`
// owner instead joins a ranked group; making its wait deferred moves it after
// all Active owners. A priority cancellation waiter adds a priority check
// between owners. These variants check the generated CFG, including the
// actual planner choices, rather than inferring coverage from symbols.
// IEEE 1800-2023 4.4.2.2-4.4.2.4, 4.6 and 4.7: retain region boundaries and
// statement/NBA ordering; the particular order between Active owners is chosen
// by the implementation.

// Three ready words cover full words, a partial last word, and a stale
// dirty word before another nonempty word. 129 counters suffice.

// SPARSE-PLAN: talos eval owner: bit=0 {{.*}} group=__talos_eval_ranked_group_0
// SPARSE-PLAN: talos eval owner: bit=129 {{.*}} group=-

// The ranked group runs from its word, in rank order before the direct owners
// of that word; the coordinator polls termination after the word. No owner
// needs the per-owner switch.
// SPARSE-LABEL: llvm.func @__talos_eval_dispatch_v1(
// SPARSE-NOT: llvm.call @__talos_eval_ranked_group_0(
// SPARSE: llvm.call @__talos_eval_dispatch_v1.word_0(
// SPARSE-NOT: segment
// SPARSE-LABEL: llvm.func @__talos_eval_dispatch_v1.word_0(
// SPARSE: %[[GROUP_BIT:.*]] = llvm.mlir.constant(1 : i64)
// SPARSE: llvm.and %{{.*}}, %[[GROUP_BIT]]
// SPARSE: llvm.cond_br %{{.*}}, ^[[GROUP:bb[0-9]+]], ^[[NEXT:bb[0-9]+]]
// SPARSE: ^[[GROUP]]:
// SPARSE-NEXT: llvm.call @__talos_eval_ranked_group_0(%arg0)
// SPARSE-NEXT: llvm.br ^[[NEXT]]
// SPARSE: ^[[NEXT]]:
// SPARSE: %[[SECOND:.*]] = llvm.mlir.constant(2 : i64)
// SPARSE: llvm.and %{{.*}}, %[[SECOND]]
// SPARSE-LABEL: llvm.func @__talos_eval_dispatch_v1.word_2(
// SPARSE: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// SPARSE: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// SPARSE: llvm.return
// SPARSE-NEXT: }

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @segments {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.counter#" {test.replicate = 129 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 3 in 0 always hierarchy "t.aaa"
    simulation.storage.decl 1 in 0 : i32 design
    simulation.code_unit.decl 133 in 0 fork hierarchy "t.cancel" {test.priority}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design {test.replicate = 129 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %n = simulation.context.storage %ctx[2] {test.replicate = 129 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %k = simulation.spawn @"counter#"(%ctx, %clk, %n) {test.replicate = 129 : i64} : !simulation.context, !clk, !int -> !simulation.process
      %q = simulation.context.storage %ctx[1] : !int
      %a = simulation.spawn @"aaa"(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %p = simulation.spawn @cancel(%ctx, %clk) {test.priority} : !simulation.context, !clk -> !simulation.process
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
    simulation.func @"counter#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64, test.replicate = 129 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %limit = arith.constant 100 : i32
      %done = arith.cmpi eq, %new, %limit : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
    simulation.func @"aaa"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>, test.deferred} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.nba.enqueue %new to %q : (i32, !int) -> ()
      cf.br ^wait
    }
    simulation.func private @cancel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 13 : i32, code_unit_id = 133 : i64, home_region = 10 : i32, internal, schedule.concurrent_cancel, schedule.detached_controls, schedule.priority_signal_resume, test.priority} {
      simulation.suspend.edge posedge %clk to ^resume {site = #schedule.continuation<id = 3>} : !clk
    ^resume:
      simulation.return
    }
  }
}
