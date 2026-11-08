// RUN: talos-opt %s --split-input-file --verify-diagnostics --materialize-native-promotion-range-index -o /dev/null

module attributes {runtime.state_bits = 64 : i64} {
  // expected-error @+1 {{range proof cache requires private zero-initialized i8 storage}}
  llvm.mlir.global internal constant @cache(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 0, 1>} : i8
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @__talos_eval_promotion_invalidate_v1() { llvm.return }
}

// -----

module attributes {runtime.state_bits = 64 : i64} {
  // expected-error @+1 {{range proof cache has no full invalidator}}
  llvm.mlir.global internal @cache(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 0, 1>} : i8
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
}

// -----

module attributes {runtime.state_bits = 64 : i64} {
  // expected-error @+1 {{range proof cache has no scoped invalidator}}
  llvm.mlir.global internal @cache(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 0, 1>} : i8
  llvm.func @__talos_eval_promotion_invalidate_v1() { llvm.return }
}

// -----

module attributes {runtime.state_bits = 64 : i64} {
  // expected-error @+1 {{proof index has an odd range list}}
  llvm.mlir.global internal @cache(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 1>} : i8
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @__talos_eval_promotion_invalidate_v1() { llvm.return }
}

// -----

module attributes {runtime.state_bits = 64 : i64} {
  // expected-error @+1 {{proof index exceeds canonical state}}
  llvm.mlir.global internal @cache(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 63, 2>} : i8
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @__talos_eval_promotion_invalidate_v1() { llvm.return }
}
