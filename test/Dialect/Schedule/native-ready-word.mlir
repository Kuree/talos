// RUN: talos-opt %s | talos-opt | FileCheck %s

// Words of a generated eval ready set, a leaf or a dirty-level word, are read
// and written whole, at a static word or a dynamic one. An entry read names
// the activation-group member it selects; an access may name its owner.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  // CHECK-LABEL: llvm.func @words(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BITS:.*]]: i64)
  llvm.func @words(%word: i64, %bits: i64) -> i64 {
    // CHECK: schedule.ready.word.load @__talos_aot_model_ingress_v1[1] {activation_entry = 65 : i32}
    %entry = schedule.ready.word.load @__talos_aot_model_ingress_v1[1] {activation_entry = 65 : i32}
    // CHECK: schedule.ready.word.load @__talos_eval_nba_held_wakes_v1[%[[WORD]] + 2] {owner = 3 : i32}
    %dirty = schedule.ready.word.load @__talos_eval_nba_held_wakes_v1[%word + 2] {owner = 3 : i32}
    // CHECK: schedule.ready.word.store %[[BITS]], @__talos_aot_model_ingress_v1[%[[WORD]]]
    schedule.ready.word.store %bits, @__talos_aot_model_ingress_v1[%word]
    // CHECK: schedule.ready.word.store %[[BITS]], @__talos_eval_nba_held_wakes_v1[0] {owner = 1 : i32}
    schedule.ready.word.store %bits, @__talos_eval_nba_held_wakes_v1[0] {owner = 1 : i32}
    %any = llvm.or %entry, %dirty : i64
    llvm.return %any : i64
  }
}
