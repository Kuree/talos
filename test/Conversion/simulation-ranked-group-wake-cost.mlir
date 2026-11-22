// RUN: talos-opt %S/simulation-ranked-group-routing.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 231 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=APART
// RUN: talos-opt %S/simulation-ranked-group-routing.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 232 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=MERGED --implicit-check-not=@__talos_eval_ranked_group_4

// A ranked member weighs its four- and two-state bodies plus 64 of pending
// and proof control, and a wake in a body counts 2. Members 3 and 4 weigh 232
// together, with one wake in each of member 3's bodies, so they share a
// helper only from a budget of 232. Counting a wake as 1 would merge them at
// 230.
// APART-LABEL: llvm.func @__talos_eval_ranked_group_3(
// APART-SAME: schedule.eval.ranked_members = array<i32: 3>
// APART-LABEL: llvm.func @__talos_eval_ranked_group_4(
// APART-SAME: schedule.eval.ranked_members = array<i32: 4>
// MERGED-LABEL: llvm.func @__talos_eval_ranked_group_3(
// MERGED-SAME: schedule.eval.ranked_members = array<i32: 3, 4>
