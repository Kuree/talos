// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// test-talos-replicate expands counter# into 513 clocked counters, each a
// direct eval owner outside any ranked group: nine ready words and one dirty
// word (runtime::DirtyReadySetLayout). The coordinator selects the lowest
// dirty word, skips and clears it when its leaf is empty, and otherwise runs
// that word's function, which tests and runs its owners in rank order. After
// the word it clears the dirty bit only if no owner of the word is pending.
// The four-state fallback flag is passed by address; errors and termination
// escape the word function (IEEE 1800-2023 4.5, 4.7, 9.2.3).

// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: %[[FALLBACK:.*]] = llvm.alloca %{{.*}} x i1
// CHECK: ^[[DISPATCH:bb[0-9]+]]:
// CHECK-NEXT: llvm.br ^[[SCAN:bb[0-9]+]]
// CHECK: ^[[SCAN]]:
// CHECK: %[[INGRESS:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK: %[[TOP_ADDRESS:.*]] = llvm.getelementptr %[[INGRESS]][72]
// CHECK: %[[TOP:.*]] = llvm.load %[[TOP_ADDRESS]]
// CHECK: %[[NINE_WORDS:.*]] = llvm.mlir.constant(511 : i64)
// CHECK: %[[DIRTY:.*]] = llvm.and %[[TOP]], %[[NINE_WORDS]]
// CHECK: llvm.cond_br %{{.*}}, ^[[FOUND:bb[0-9]+]], ^[[EMPTY:bb[0-9]+]]
// CHECK: ^[[CLEAR:bb[0-9]+]](%[[CLEARED:.*]]: i64):
// CHECK: %[[PARENT:.*]] = llvm.lshr %[[CLEARED]],
// CHECK: %[[DIRTY_INDEX:.*]] = llvm.add %[[PARENT]],
// CHECK: %[[DIRTY_ADDRESS:.*]] = llvm.getelementptr %{{.*}}[%[[DIRTY_INDEX]]]
// CHECK: llvm.load %[[DIRTY_ADDRESS]]
// CHECK: llvm.store %{{.*}}, %[[DIRTY_ADDRESS]]
// CHECK-NEXT: llvm.br ^[[DISPATCH]]
// CHECK: ^[[GATE:bb[0-9]+]](%[[WORD:.*]]: i64):
// CHECK: %[[LEAF_ADDRESS:.*]] = llvm.getelementptr %{{.*}}[%[[WORD]]]
// CHECK: %[[LEAF:.*]] = llvm.load %[[LEAF_ADDRESS]]
// CHECK: %[[NONEMPTY:.*]] = llvm.icmp "ne" %[[LEAF]],
// CHECK-NEXT: llvm.cond_br %[[NONEMPTY]], ^[[SWITCH:bb[0-9]+]](%[[WORD]] : i64), ^[[CLEAR]](%[[WORD]] : i64)
// CHECK: ^[[FOUND]]:
// CHECK: "llvm.intr.cttz"(%[[DIRTY]]) <{is_zero_poison = true}>
// CHECK: llvm.br ^[[GATE]](
// CHECK: ^[[SWITCH]](%[[SELECTED:.*]]: i64):
// CHECK-NEXT: llvm.switch %[[SELECTED]] : i64, ^{{bb[0-9]+}} [
// CHECK-NEXT: 0: ^[[WORD0:bb[0-9]+]],
// CHECK: 8: ^[[WORD8:bb[0-9]+]]
// CHECK-NEXT: ]
// After a successful word the coordinator polls termination once.
// CHECK: ^[[AFTER:bb[0-9]+]](%[[RAN:.*]]: i64, %[[STATUS:.*]]: i32):
// CHECK: llvm.cond_br %{{.*}}, ^[[POLL:bb[0-9]+]], ^{{bb[0-9]+}}(%[[STATUS]] : i32)
// CHECK: ^[[POLL]]:
// CHECK-NEXT: llvm.mlir.addressof @__talos_periodic_termination_v1
// CHECK: llvm.cond_br %{{.*}}, ^[[RECHECK:bb[0-9]+]], ^{{bb[0-9]+}}
// CHECK: ^[[RECHECK]]:
// CHECK: llvm.getelementptr %{{.*}}[%[[RAN]]]
// CHECK: llvm.cond_br %{{.*}}, ^[[DISPATCH]], ^[[CLEAR]](%[[RAN]] : i64)
// CHECK: ^[[WORD0]]:
// CHECK-NEXT: %[[CALLED:.*]] = llvm.call @__talos_eval_dispatch_v1.word_0(%arg1, %[[FALLBACK]])
// CHECK-NEXT: llvm.br ^[[AFTER]](%[[SELECTED]], %[[CALLED]] : i64, i32)
// CHECK: ^[[WORD8]]:
// CHECK-NEXT: llvm.call @__talos_eval_dispatch_v1.word_8(%arg1, %[[FALLBACK]])

// Owners run in bit order; each consumes its own bit and polls termination.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1.word_0(%arg0: !llvm.ptr, %arg1: !llvm.ptr) -> i32
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<dispatch>
// CHECK: %[[FIRST:.*]] = llvm.mlir.constant(1 : i64)
// CHECK: llvm.and %{{.*}}, %[[FIRST]]
// CHECK: llvm.cond_br %{{.*}}, ^[[RUN0:bb[0-9]+]], ^[[NEXT0:bb[0-9]+]]
// CHECK: ^[[NEXT0]]:
// CHECK: %[[SECOND:.*]] = llvm.mlir.constant(2 : i64)
// CHECK: llvm.and %{{.*}}, %[[SECOND]]
// CHECK: llvm.store %{{.*}}, %arg1 {{.*}} : i1, !llvm.ptr
// CHECK-NEXT: llvm.call @__talos_direct_fragment_{{.*}}.__talos_execute(%arg0)
// The proven two-state call's trivial trusted wrapper is inlined, so the
// word calls the owner's path dispatcher directly.
// CHECK: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0) {schedule.eval.direct_call}
// CHECK: llvm.mlir.addressof @__talos_periodic_termination_v1
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1.word_8(
// CHECK-NOT: llvm.func
// CHECK: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// CHECK-NOT: llvm.call @__talos_eval_path_dispatch
// CHECK: llvm.return

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @segments {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.counter#" {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %false = arith.constant false
      simulation.ref.store %false to %clk : i1, !clk
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %n = simulation.context.storage %ctx[1] {test.replicate = 513 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %k = simulation.spawn @"counter#"(%ctx, %clk, %n) {test.replicate = 513 : i64} : !simulation.context, !clk, !int -> !simulation.process
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
    simulation.func @"counter#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64, test.replicate = 513 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
  }
}
