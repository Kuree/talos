// RUN: talos-opt %S/simulation-ranked-group-routing.mlir '--test-talos-set-module-attributes=attrs="{schedule.native.max_inline_ops = 300 : i64}"' > %t.input.mlir
// RUN: talos-opt %t.input.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=PLAN < %t.llvm.mlir

// A configured routing SCC crosses a native size-budget split. The shared
// dispatcher selects one finite segment. Its direct calls retain the bounded
// helpers and their predicated dataflow; backward publications remain pending
// for another segment activation, without a global dispatch at the size split.
// PLAN-LABEL: llvm.func @__talos_eval_ranked_group_1(
// PLAN-SAME: schedule.eval.ranked_members = array<i32: 1>
// PLAN-LABEL: llvm.func @__talos_eval_ranked_group_2(
// PLAN-SAME: schedule.eval.ranked_members = array<i32: 2>
// PLAN-LABEL: llvm.func @__talos_eval_ranked_group_3(
// PLAN-SAME: schedule.eval.ranked_members = array<i32: 3, 4>
// PLAN-LABEL: llvm.func @__talos_eval_ranked_group_1.segment(
// PLAN-SAME: schedule.eval.segment_helpers = [@__talos_eval_ranked_group_1, @__talos_eval_ranked_group_2, @__talos_eval_ranked_group_3]
// One test skips all the chunks of an idle ready word.
// PLAN: %[[READY:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// PLAN-NEXT: %[[WORD:.*]] = llvm.load %[[READY]]
// PLAN-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// PLAN-NEXT: %[[ACTIVE:.*]] = llvm.icmp "ne" %[[WORD]], %[[ZERO]]
// PLAN-NEXT: llvm.cond_br %[[ACTIVE]], ^[[BODY:bb[0-9]+]], ^[[AFTER:bb[0-9]+]]
// Each chunk still reads the word itself, after earlier chunks published to it.
// PLAN: ^[[BODY]]:
// PLAN-NEXT: llvm.load %[[READY]]
// PLAN: llvm.call @__talos_eval_ranked_group_1(
// PLAN: llvm.load %[[READY]]
// PLAN: llvm.call @__talos_eval_ranked_group_2(
// PLAN: llvm.load %[[READY]]
// PLAN: llvm.call @__talos_eval_ranked_group_3(
// PLAN: ^[[AFTER]]:
// PLAN-NEXT: llvm.return
// PLAN-LABEL: llvm.func @__talos_eval_dispatch_v1(
// PLAN: llvm.call @__talos_eval_ranked_group_1.segment(
// PLAN-NOT: llvm.call @__talos_eval_ranked_group_2(
