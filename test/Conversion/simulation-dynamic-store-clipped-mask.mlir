// RUN: talos-opt %S/simulation-dynamic-store-proof-range.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// IEEE 1800-2023 11.5.1: a partially out-of-range select updates only the
// in-range bits. Reuse the dynamic-store fixture's unaligned 129-bit root,
// which shares bytes with its neighbors. Clamping a high partial select to
// the last full window must discard mask bits shifted beyond that window.
// Otherwise a byte store zeroes neighboring variables in both state planes.
// CHECK-LABEL: llvm.func @write_disjoint(
// CHECK: %[[FULL:.*]] = llvm.mlir.constant(255 : i16)
// CHECK-NEXT: %[[LOW_CLIP:.*]] = llvm.lshr %[[FULL]], %{{.*}} : i16
// CHECK-NEXT: %[[SHIFTED:.*]] = llvm.shl %[[LOW_CLIP]], %{{.*}} : i16
// CHECK-NEXT: %[[CLIPPED:.*]] = llvm.and %[[SHIFTED]], %[[FULL]] : i16
// CHECK-NEXT: %[[POSITIONED:.*]] = llvm.shl %[[CLIPPED]], %{{.*}} : i16
// CHECK: %[[MASK:.*]] = llvm.select %{{.*}}, %[[POSITIONED]], %{{.*}} : i1, i16
// CHECK: %[[DIFF:.*]] = llvm.xor %{{.*}}, %{{.*}} : i16
// CHECK-NEXT: %[[VALUE_BITS:.*]] = llvm.and %[[MASK]], %[[DIFF]] : i16
// CHECK-NEXT: %[[VALUE:.*]] = llvm.xor %{{.*}}, %[[VALUE_BITS]] : i16
// CHECK: llvm.store %[[VALUE]],
// CHECK: %[[UNKNOWN_DIFF:.*]] = llvm.xor %{{.*}}, %{{.*}} : i16
// CHECK-NEXT: %[[UNKNOWN_BITS:.*]] = llvm.and %[[MASK]], %[[UNKNOWN_DIFF]] : i16
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.xor %{{.*}}, %[[UNKNOWN_BITS]] : i16
// CHECK: llvm.store %[[UNKNOWN]],
// CHECK: llvm.return
