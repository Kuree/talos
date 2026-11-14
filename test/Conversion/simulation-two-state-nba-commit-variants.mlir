// RUN: talos-opt %S/simulation-to-llvm-coroutine-aot-nba.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native_scheduler = 3 : i32, native.two_state}"},simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' \
// RUN:   | FileCheck %s --implicit-check-not=@__talos_aot_static_nba_commit_two_state_v1 --implicit-check-not=@__talos_eval_static_nba_publication_two_state_v1 --implicit-check-not=@__talos_state_unknown

// A two-state build eliminates the unknown plane and all staged unknown data
// module-wide, so a canonical two-state NBA commit would copy the four-state
// one. Its callers keep the four-state commit, which takes the variant's
// cache-line alignment; only the fast variant, specialized to the NBA region,
// is cloned.
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1
// CHECK: llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1
// CHECK: llvm.call @__talos_aot_static_nba_commit_v1
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK-SAME: alignment = 128 : i64
// CHECK-LABEL: llvm.func internal @__talos_aot_static_nba_commit_two_state_fast_v1(
// CHECK-SAME: alignment = 128 : i64
