// RUN: talos-opt %s --materialize-native-promotion-range-index='bucket-min-entries=1' | FileCheck %s

// A whole-memory dependency would need one bucket record per word, so only it
// stays in the interval tree and the narrow certificate keeps its bucket. X/Z
// changes must reach every intersecting proof (IEEE 1800-2023 6.3.1, 6.11.2),
// so both hooks consult both tables.
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_proof_bucket_starts_v1(dense<[0, 0, 1]>
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_proof_bucket_records_v1(dense<2>
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_proof_dependencies_v1(dense<{{\[\[}}128, 8320, 8320, 1]]>
// CHECK-LABEL: llvm.func @__talos_eval_promotion_recheck_range_v1(
// CHECK: llvm.call @talos_rt_v1_native_promotion_recheck_buckets
// CHECK: llvm.call @talos_rt_v1_native_promotion_recheck_ranges
// CHECK-LABEL: llvm.func @__talos_eval_promotion_invalidate_range_v1(
// CHECK: llvm.call @talos_rt_v1_native_promotion_invalidate_buckets
// CHECK: llvm.call @talos_rt_v1_native_promotion_invalidate_ranges
module attributes {runtime.state_bits = 16384 : i64} {
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.mlir.global internal @__talos_eval_fast_nba_roots_v1(dense<3> : tensor<1xi64>) {
    schedule.eval.nba_proof_dependencies = [
      #schedule.nba_proof_dependency<bit = 0 : i64, ranges = [64, 2]>,
      #schedule.nba_proof_dependency<bit = 1 : i64, ranges = [128, 8192]>
    ]} : !llvm.array<1 x i64>
}
