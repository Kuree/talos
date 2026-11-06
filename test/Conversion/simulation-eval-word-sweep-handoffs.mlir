// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.priority erase},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.sparse.mlir 2> %t.sparse.trace
// RUN: FileCheck %s --check-prefix=SPARSE < %t.sparse.mlir
// RUN: FileCheck %s --check-prefix=SPARSE-PLAN < %t.sparse.trace
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.priority erase},test-talos-edit-attributes{has=test.deferred set="{resume_region = 3 : i32}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.deferred.mlir 2> %t.deferred.trace
// RUN: FileCheck %s --check-prefix=DEFERRED < %t.deferred.mlir
// RUN: FileCheck %s --check-prefix=DEFERRED-PLAN < %t.deferred.trace
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.deferred set="{resume_region = 3 : i32}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.priority.mlir 2> %t.priority.trace
// RUN: FileCheck %s --check-prefix=PRIORITY < %t.priority.mlir

// The counter owners cannot fuse because they may terminate. The pure `aaa`
// owner instead joins a ranked group; making its wait deferred moves it after
// all Active owners. A priority cancellation waiter adds a priority check
// between owners. These variants check the generated CFG, including the
// actual planner choices, rather than inferring coverage from symbols.
// IEEE 1800-2023 4.4.2.2-4.4.2.4, 4.6 and 4.7: retain region boundaries and
// statement/NBA ordering; the particular order between Active owners is chosen
// by the implementation.

// SPARSE-PLAN: talos eval owner: bit=0 {{.*}} group=__talos_eval_ranked_group_0
// SPARSE-PLAN: talos eval owner: bit=513 {{.*}} group=-

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
// SPARSE-LABEL: llvm.func @__talos_eval_dispatch_v1.word_8(
// SPARSE: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// SPARSE: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// SPARSE: llvm.return
// SPARSE-NEXT: }

// DEFERRED-PLAN: talos eval owner: bit=512 {{.*}} group=- {{.*}}{{$}}
// DEFERRED-PLAN-NEXT: talos eval owner: bit=513 {{.*}} deferred{{$}}

// Word 8 holds Active owner 512 and deferred owner 513. The sweep gates that
// word (and only that word) on its Active bit; once no Active word is dirty, the coordinator
// scans the deferred bits directly, checks for a finish request, takes the
// Inactive cut and runs the deferred owner from the per-owner switch.
// DEFERRED-LABEL: llvm.func @__talos_eval_dispatch_v1(
// DEFERRED: llvm.switch %[[DEFERRED_BIT:.*]] : i64, ^{{bb[0-9]+}} [
// DEFERRED-NEXT: 513: ^
// DEFERRED-NEXT: ]
// DEFERRED: %[[INACTIVE:.*]] = llvm.mlir.constant(2 : i64)
// DEFERRED-NEXT: %[[PENDING:.*]] = llvm.and %{{.*}}, %[[INACTIVE]]
// DEFERRED: %[[MIXED:.*]] = llvm.mlir.constant(8 : i64)
// DEFERRED-NEXT: %[[IS_MIXED:.*]] = llvm.icmp "eq" %{{.*}}, %[[MIXED]]
// DEFERRED-NEXT: llvm.cond_br %[[IS_MIXED]], ^[[SHARED:bb[0-9]+]], ^{{bb[0-9]+}}(
// DEFERRED-NEXT: ^[[SHARED]]:
// DEFERRED-NEXT: %[[ACTIVE:.*]] = llvm.mlir.constant(1 : i64)
// DEFERRED-NEXT: llvm.and %{{.*}}, %[[ACTIVE]]
// DEFERRED: "llvm.intr.cttz"(%[[PENDING]])
// DEFERRED: llvm.call @talos_rt_v1_scheduler_termination_requested(
// DEFERRED-LABEL: llvm.func @__talos_eval_dispatch_v1.word_8(
// DEFERRED: llvm.mlir.constant(1 : i64)
// DEFERRED-NOT: llvm.mlir.constant(2 : i64)
// DEFERRED-NOT: llvm.func
// DEFERRED: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// DEFERRED-NOT: llvm.mlir.constant(2 : i64)
// DEFERRED: llvm.func

// The priority cancellation waiter is runtime-owned, so this variant keeps a
// runtime calendar; with `aaa` deferred, word 8 is shared with the deferred
// owner. The NBA cut drains runtime work, then the deferred owner runs from
// the per-owner switch, which must survive although only the commit path
// emitted after the sweep branches to it. Priority work is polled after each
// owner of a word: a pending priority signal returns TALOS_RT_AOT_CHECKPOINT
// (20) before the next owner (IEEE 1800-2023 4.4.2.3-4.4.2.4).
// PRIORITY-LABEL: llvm.func internal @__talos_eval_dispatch_v1.__talos_pending(
// PRIORITY: llvm.call @talos_rt_v1_scheduler_prepare_eval_nba
// PRIORITY: llvm.switch %{{.*}} : i64, ^{{bb[0-9]+}} [
// PRIORITY-NEXT: 513: ^
// PRIORITY-NEXT: ]
// PRIORITY-LABEL: llvm.func @__talos_eval_dispatch_v1.word_0(
// PRIORITY: llvm.call @talos_rt_v1_scheduler_priority_signal_pending(%arg0)
// PRIORITY-NEXT: llvm.mlir.constant(0 : i32)
// PRIORITY-NEXT: llvm.icmp "ne"
// PRIORITY-NEXT: llvm.mlir.constant(20 : i32)

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @segments {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.counter#" {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 3 in 0 always hierarchy "t.aaa"
    simulation.storage.decl 1 in 0 : i32 design
    simulation.code_unit.decl 517 in 0 fork hierarchy "t.cancel" {test.priority}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %n = simulation.context.storage %ctx[2] {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %k = simulation.spawn @"counter#"(%ctx, %clk, %n) {test.replicate = 513 : i64} : !simulation.context, !clk, !int -> !simulation.process
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
    simulation.func @"counter#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64, test.replicate = 513 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
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
    simulation.func private @cancel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 13 : i32, code_unit_id = 517 : i64, home_region = 10 : i32, internal, schedule.concurrent_cancel, schedule.detached_controls, schedule.priority_signal_resume, test.priority} {
      simulation.suspend.edge posedge %clk to ^resume {site = #schedule.continuation<id = 3>} : !clk
    ^resume:
      simulation.return
    }
  }
}
