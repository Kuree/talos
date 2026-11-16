// RUN: talos-opt %S/simulation-to-llvm-coroutine-aot-nba-two-state-stage.mlir --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// IEEE 1800-2023 4.5, 4.6(b), 10.4.2: a four-state fallback can hand a
// barrier to runtime even when every destination is static. Export compact
// capture metadata before runtime can inspect it; retain the captured value
// and unknown planes. The companion fixture checks that the hot stages still
// omit these fields. A word is visited only when it has a compact dirty root
// or an earlier export left one live; then empty dirty bits clear stale
// canonical validity/masks. A coordinator return exports only when it yields
// with staging intact or must clear a live export.
// CHECK-LABEL: module @inductive
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: llvm.call @__talos_eval_export_nba_metadata_on_return_v1()
// CHECK-LABEL: llvm.func @__talos_aot_runtime_nba_commit_v1(
// CHECK-NOT: llvm.call @__talos_eval_export_nba_metadata_v1()
// CHECK: llvm.call @talos_rt_v1_static_nba_commit_roots
// CHECK-LABEL: llvm.func internal @__talos_eval_export_nba_metadata_v1()
// CHECK: %[[DIRTY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// CHECK: %[[SUMMARY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_summary_v1
// CHECK: %[[SHADOW:.*]] = llvm.mlir.addressof @__talos_eval_nba_exported_roots_v1
// CHECK: %[[WORD:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i64
// CHECK: %[[BITS:.*]] = llvm.and %[[WORD]], %{{.*}} : i64
// CHECK: %[[SHADOW_ADDR:.*]] = llvm.getelementptr %[[SHADOW]][0]
// CHECK: %[[PREVIOUS:.*]] = llvm.load %[[SHADOW_ADDR]]
// CHECK: %[[ANY:.*]] = llvm.or %[[BITS]], %[[PREVIOUS]] : i64
// CHECK: %[[VISIT:.*]] = llvm.icmp "ne" %[[ANY]]
// CHECK: llvm.cond_br %[[VISIT]], ^[[ROOTS:bb[0-9]+]], ^[[NEXT:bb[0-9]+]](
// CHECK: ^[[ROOTS]]:
// CHECK: %[[PRESENT:.*]] = llvm.icmp "ne"
// CHECK: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_0
// CHECK-NOT: llvm.getelementptr %[[ACC]][0]
// CHECK-NOT: llvm.getelementptr %[[ACC]][32]
// CHECK: %[[MASK_ADDR:.*]] = llvm.getelementptr %[[ACC]][64]
// CHECK: %[[MASK:.*]] = llvm.select %[[PRESENT]], %{{.*}}, %{{.*}} : i1, i64
// CHECK: llvm.store %[[MASK]], %[[MASK_ADDR]]
// CHECK: %[[VALID:.*]] = llvm.zext %[[PRESENT]] : i1 to i32
// CHECK: %[[VALID_ADDR:.*]] = llvm.getelementptr %[[ACC]][96]
// CHECK: llvm.store %[[VALID]], %[[VALID_ADDR]]
// CHECK: %[[REGION:.*]] = llvm.mlir.constant(2 : i32)
// CHECK: %[[REGION_ADDR:.*]] = llvm.getelementptr %[[ACC]][100]
// CHECK: llvm.store %[[REGION]], %[[REGION_ADDR]]
// CHECK: llvm.getelementptr %[[SUMMARY]][0]
// CHECK: llvm.store %[[BITS]], %[[SHADOW_ADDR]]
// CHECK: llvm.mlir.addressof @__talos_eval_nba_exported_live_v1
// CHECK-LABEL: llvm.func internal @__talos_eval_export_nba_metadata_on_return_v1()
// CHECK: %[[LIVE:.*]] = llvm.load %{{.*}} -> i8
// CHECK: llvm.icmp "ne" %[[LIVE]]
// CHECK: %[[YIELD:.*]] = llvm.load %{{.*}} -> i32
// CHECK: llvm.icmp "eq" %[[YIELD]]
// CHECK: llvm.cond_br %{{.*}}, ^[[EXPORT:bb[0-9]+]], ^[[DONE:bb[0-9]+]]
// CHECK: ^[[EXPORT]]:
// CHECK-NEXT: llvm.call @__talos_eval_export_nba_metadata_v1()
// CHECK-LABEL: module @selected
// CHECK: llvm.call @__talos_eval_export_nba_metadata_on_return_v1()
// CHECK: llvm.func internal @__talos_eval_export_nba_metadata_v1()
