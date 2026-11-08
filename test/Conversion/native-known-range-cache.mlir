// RUN: talos-opt %s --materialize-native-promotion-range-index -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-translate --mlir-to-llvmir %t.mlir | %llvm_dist/bin/opt -passes=verify -disable-output
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-p:32:32-i64:64\", llvm.target_triple = \"wasm32-unknown-unknown\"}"' --materialize-native-promotion-range-index | talos-translate --mlir-to-llvmir | %llvm_dist/bin/opt -passes=verify -disable-output

// LRM 6.3.1: this private certificate covers exactly bits 1..3 and 8.
// It certifies no owner, route, or group. Both scoped X/Z loss and the full
// context-reset invalidator must revoke it; gaining knownness cannot set it.
// CHECK: @__talos_eval_proof_certificates_v1
// CHECK-LABEL: llvm.func @__talos_eval_promotion_invalidate_v1
// CHECK: llvm.mlir.addressof @cached_known
// CHECK: llvm.store
// CHECK: llvm.return
module attributes {runtime.state_bits = 64 : i64} {
  llvm.mlir.global internal @cached_known(0 : i8) {schedule.eval.known_range_dependencies = array<i64: 1, 3, 8, 1>} : i8
  llvm.func @__talos_eval_promotion_invalidate_range_v1(i64, i64)
  llvm.func @__talos_eval_promotion_invalidate_v1() {
    llvm.return
  }
  llvm.func @test_range_cache() -> !llvm.ptr {
    %p = llvm.mlir.addressof @cached_known : !llvm.ptr
    llvm.return %p : !llvm.ptr
  }
}
