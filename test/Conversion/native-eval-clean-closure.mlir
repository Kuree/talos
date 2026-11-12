// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=full},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),prepare-native-schedule-inputs,schedule-plan-native-state,prepare-native-process-frames,schedule-plan-native-actors,schedule-specialize-native-captures,convert-simulation-to-native-schedule,prepare-native-managed-roots,schedule-mark-clean-native-nba,schedule-specialize-native-eval)' -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-opt %s --emit-bytecode -o %t.bc
// RUN: talos-opt %t.bc --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=full},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),prepare-native-schedule-inputs,schedule-plan-native-state,prepare-native-process-frames,schedule-plan-native-actors,schedule-specialize-native-captures,convert-simulation-to-native-schedule,prepare-native-managed-roots,schedule-mark-clean-native-nba,schedule-specialize-native-eval)' -o %t.roundtrip
// RUN: diff %t.mlir %t.roundtrip

// Writable VPI keeps canonical fallback bodies (LRM 38.34/10.6.2). Clean
// evaluator copies must share one cloned helper closure, keep lexical scopes,
// and resolve a preexisting clean-name collision without rebinding its users.
// CHECK-LABEL: simulation.func @first(
// CHECK-SAME: schedule.eval.body = @[[FIRST:first.__talos_eval_body_[0-9]+.__talos_clean]]
// CHECK: simulation.call @shared(
// CHECK-LABEL: simulation.func @second(
// CHECK-SAME: schedule.eval.body = @[[SECOND:second.__talos_eval_body_[0-9]+.__talos_clean]]
// CHECK: simulation.call @shared(
// CHECK-LABEL: simulation.func private @shared(
// CHECK-NOT: schedule.native.clean_eval_body
// CHECK: simulation.call @leaf(
// CHECK-LABEL: simulation.func private @leaf(
// CHECK-NOT: schedule.native.clean_eval_body
// CHECK: arith.constant 7 : i32
// CHECK-LABEL: simulation.func private @shared.__talos_clean(
// CHECK-NOT: schedule.native.clean_eval_body
// CHECK: arith.constant 99 : i32
// CHECK-LABEL: simulation.func private @first.__talos_eval_body_0(
// CHECK-NOT: schedule.eval.raw_captures
// CHECK: simulation.call @shared(
// CHECK-LABEL: simulation.func private @second.__talos_eval_body_0(
// CHECK-NOT: schedule.eval.raw_captures
// CHECK: simulation.call @shared(
// CHECK: simulation.code_unit.decl [[FIRST_ID:[0-9]+]] in 1 function hierarchy "[[FIRST]]"
// CHECK: simulation.func private @[[FIRST]](
// CHECK-SAME: code_unit_id = [[FIRST_ID]] : i64
// CHECK-SAME: schedule.eval.raw_captures
// CHECK-SAME: schedule.native.clean_eval_body
// CHECK: simulation.call @[[SHARED:shared.__talos_clean_[0-9]+]](
// CHECK: simulation.code_unit.decl [[SECOND_ID:[0-9]+]] in 1 function hierarchy "[[SECOND]]"
// CHECK: simulation.func private @[[SECOND]](
// CHECK-SAME: code_unit_id = [[SECOND_ID]] : i64
// CHECK: simulation.call @[[SHARED]](
// CHECK: simulation.code_unit.decl [[SHARED_ID:[0-9]+]] in 2 function hierarchy "[[SHARED]]"
// CHECK: simulation.func private @[[SHARED]](
// CHECK-SAME: code_unit_id = [[SHARED_ID]] : i64
// CHECK-SAME: schedule.native.clean_eval_body
// CHECK: simulation.call @[[LEAF:leaf.__talos_clean]](
// CHECK: simulation.code_unit.decl [[LEAF_ID:[0-9]+]] in 3 function hierarchy "[[LEAF]]"
// CHECK: simulation.func private @[[LEAF]](
// CHECK-SAME: code_unit_id = [[LEAF_ID]] : i64
// CHECK-SAME: schedule.native.clean_eval_body
// CHECK: arith.constant 7 : i32

!c = !simulation.context
!r = !simulation.ref<i1>
module attributes {native.closed_executable, schedule.native.max_inline_ops = 0 : i64, schedule.native_scheduler = 3 : i32, llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @clean_closure {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0 hierarchy "top"
    simulation.scope.decl 2 parent 1 hierarchy "top.shared"
    simulation.scope.decl 3 parent 1 hierarchy "top.leaf"
    simulation.storage.decl 0 in 1 : i1 design
    simulation.storage.decl 1 in 1 : i32 design
    simulation.storage.decl 2 in 1 : i32 design
    simulation.code_unit.decl 1 in 1 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 1 always hierarchy "top.clock"
    simulation.code_unit.decl 3 in 1 always hierarchy "top.first"
    simulation.code_unit.decl 4 in 1 always hierarchy "top.second"
    simulation.code_unit.decl 5 in 2 function hierarchy "top.shared"
    simulation.code_unit.decl 6 in 3 function hierarchy "top.leaf"
    simulation.code_unit.decl 7 in 1 function hierarchy "top.collision"
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !r
      %clock = simulation.spawn @clock(%ctx, %clk) : !c, !r -> !simulation.process
      %first = simulation.spawn @first(%ctx, %clk) : !c, !r -> !simulation.process
      %second = simulation.spawn @second(%ctx, %clk) : !c, !r -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !c {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      %old = simulation.ref.load %clk : !r -> i1
      %one = arith.constant true
      %next = arith.xori %old, %one : i1
      simulation.ref.store %next to %clk : i1, !r
      cf.br ^wait
    }
    simulation.func @first(%ctx: !c {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !r
    ^body:
      %v = simulation.call @shared(%ctx) : (!c) -> i32
      %out = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      simulation.ref.store %v to %out : i32, !simulation.ref<i32>
      cf.br ^wait
    }
    simulation.func @second(%ctx: !c {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !r
    ^body:
      %v = simulation.call @shared(%ctx) : (!c) -> i32
      %out = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      simulation.ref.store %v to %out : i32, !simulation.ref<i32>
      cf.br ^wait
    }
    simulation.func private @shared(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.call @leaf(%ctx) : (!c) -> i32
      simulation.return %v : i32
    }
    simulation.func private @leaf(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %v = arith.constant 7 : i32
      simulation.return %v : i32
    }
    simulation.func private @shared.__talos_clean(%ctx: !c {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %v = arith.constant 99 : i32
      simulation.return %v : i32
    }
  }
}
