// RUN: talos-opt %s --materialize-native-group-promotion-readiness --materialize-native-promotion-range-index | FileCheck %s
// RUN: talos-opt %s --materialize-native-group-promotion-readiness --materialize-native-promotion-range-index | talos-opt --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))' | %llvm_dist/bin/mlir-opt --convert-arith-to-llvm --convert-cf-to-llvm | talos-translate --mlir-to-llvmir | %llvm_dist/bin/opt -passes=verify -disable-output

// LRM 6.3.1: a knownness query tests exactly the union of required bits.
// Three one-bit ranges in one physical word need one load with their ORed
// mask; intervening bits remain unobserved. A million-bit contiguous interior
// stays one compact run. Its partial boundary masks preserve bit63 and the
// eight-bit hole before the final required bit, without expanding per word.
// Unsorted/repeated member ranges have the same exact union; a whole-word gap
// in the third domain must remain absent from the query.
// Runtime coverage in ../Runtime/native-promotion-word-mask-compaction.test
// checks both encodings against a scalar bit-union oracle, including holes,
// long-run boundaries, stale hints, and unknown-state preservation.
// CHECK-DAG: @__talos_eval_group_promotion_domains_v1(dense<[0, 1, 1, 4, 4, 6]>
// CHECK-DAG: @__talos_eval_group_promotion_ranges_v1(dense<[-9223372036854775808, 65793, -9223372036854775808, -9223372036854775808, 1, 16384, -9223372036854759424, 256, -9223372036854775808, 1, -9223372036854775806, 1]> : tensor<12xi64>)
// CHECK-DAG: @__talos_eval_group_promotion_hints_v1(dense<0> : tensor<6xi64>)

#member0 = #schedule.kernel_proof_dependency<latch = 0 : i64, pendingBit = 0 : i64, ranges = [16, 1, 0, 1, 8, 1, 8, 1]>
#member1 = #schedule.kernel_proof_dependency<latch = 1 : i64, pendingBit = 1 : i64, ranges = [1048584, 1, 63, 1048513]>
#member2 = #schedule.kernel_proof_dependency<latch = 2 : i64, pendingBit = 2 : i64, ranges = [0, 1, 128, 1]>
#group0 = #schedule.group_proof_dependency<domain = 0 : i64, members = [0], ranges = [0, 1, 8, 1, 16, 1]>
#group1 = #schedule.group_proof_dependency<domain = 1 : i64, members = [1], ranges = [63, 1048513, 1048584, 1]>
#group2 = #schedule.group_proof_dependency<domain = 2 : i64, members = [2], ranges = [0, 1, 128, 1]>
module attributes {runtime.state_bits = 1048600 : i64} {
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16386xi64>) : !llvm.array<16386 x i64>
  llvm.mlir.global internal @__talos_eval_kernel_promotion_latched_v1(dense<0> : tensor<3xi8>) {schedule.eval.kernel_proof_dependencies = [#member0, #member1, #member2]} : !llvm.array<3 x i8>
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<7> : tensor<1xi64>) : !llvm.array<1 x i64>
  llvm.mlir.global internal @__talos_eval_group_promotion_latched_v1(dense<0> : tensor<3xi8>) {schedule.eval.group_proof_dependencies = [#group0, #group1, #group2]} : !llvm.array<3 x i8>
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @compaction_test_unknown() -> !llvm.ptr {
    %p = schedule.state.address @__talos_state_unknown : !llvm.ptr
    llvm.return %p : !llvm.ptr
  }
  llvm.func @compaction_test_latches() -> !llvm.ptr {
    %p = llvm.mlir.addressof @__talos_eval_group_promotion_latched_v1 : !llvm.ptr
    llvm.return %p : !llvm.ptr
  }
}
