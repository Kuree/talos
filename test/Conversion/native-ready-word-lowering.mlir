// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-ready-words))' | FileCheck %s --implicit-check-not=schedule.ready

// A ready set word access becomes a whole-word LLVM access of the set's
// global with 8-byte alignment: the set's address once per function, at the
// start of its entry block in the order of first use, then word 0 at that
// address, a byte GEP to another static word, or an i64 GEP by a dynamic word
// and a byte GEP to its static words. An owner and an activation entry become
// the access's tags, as the LLVM form of a group carries them; other
// dialects' annotations stay with the access.
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  llvm.mlir.global internal @__talos_eval_nba_held_wakes_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  // CHECK-LABEL: llvm.func @words(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BITS:.*]]: i64, %[[C:.*]]: i1)
  // CHECK-NEXT: %[[INGRESS:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
  // CHECK-NEXT: %[[HELD:.*]] = llvm.mlir.addressof @__talos_eval_nba_held_wakes_v1 : !llvm.ptr
  // CHECK-NEXT: %[[LEAF:.*]] = llvm.load %[[INGRESS]] {alignment = 8 : i64, schedule.eval.activation_entry = 0 : i32} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[DIRTY:.*]] = llvm.getelementptr %[[INGRESS]][16] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[DIRTY]] {alignment = 8 : i64, schedule.eval.group_owner = 3 : i32} : !llvm.ptr -> i64
  // CHECK-NEXT: llvm.cond_br %[[C]]
  // CHECK: ^bb1:
  // CHECK-NEXT: %[[AT:.*]] = llvm.getelementptr %[[HELD]][%[[WORD]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: llvm.store %[[BITS]], %[[AT]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK-NEXT: %[[BASE:.*]] = llvm.getelementptr %[[HELD]][%[[WORD]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: %[[UP:.*]] = llvm.getelementptr %[[BASE]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[UP]] {alignment = 8 : i64, test.tag} : !llvm.ptr -> i64
  // CHECK: ^bb2:
  // CHECK-NEXT: llvm.store %[[BITS]], %[[INGRESS]] {alignment = 8 : i64} : i64, !llvm.ptr
  llvm.func @words(%word: i64, %bits: i64, %c: i1) -> i64 {
    %leaf = schedule.ready.word.load @__talos_aot_model_ingress_v1[0] {activation_entry = 0 : i32}
    %dirty = schedule.ready.word.load @__talos_aot_model_ingress_v1[2] {owner = 3 : i32}
    llvm.cond_br %c, ^dynamic, ^done
  ^dynamic:
    schedule.ready.word.store %bits, @__talos_eval_nba_held_wakes_v1[%word]
    %up = schedule.ready.word.load @__talos_eval_nba_held_wakes_v1[%word + 1] {test.tag}
    llvm.br ^done
  ^done:
    schedule.ready.word.store %bits, @__talos_aot_model_ingress_v1[0]
    %any = llvm.or %leaf, %dirty : i64
    llvm.return %any : i64
  }
  // An index defined in the access's block takes its words' addresses right
  // after it, in order of first use, each static word with its own i64 GEP
  // (as the cost model charges it); every access of the same word in the
  // block shares its address.
  // CHECK-LABEL: llvm.func @local_index(
  // CHECK-SAME: %[[W:.*]]: i64, %[[V:.*]]: i64)
  // CHECK-NEXT: %[[SET:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
  // CHECK-NEXT: %[[ONE:.*]] = llvm.mlir.constant(1 : i64) : i64
  // CHECK-NEXT: %[[I:.*]] = llvm.add %[[W]], %[[ONE]] : i64
  // CHECK-NEXT: %[[AT:.*]] = llvm.getelementptr %[[SET]][%[[I]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: %[[NEXT:.*]] = llvm.getelementptr %[[SET]][%[[I]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: %[[UP:.*]] = llvm.getelementptr %[[NEXT]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: %[[OLD:.*]] = llvm.load %[[AT]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: llvm.store %[[V]], %[[AT]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK-NEXT: %[[ABOVE:.*]] = llvm.load %[[UP]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[AGAIN:.*]] = llvm.load %[[AT]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: llvm.or %[[OLD]], %[[ABOVE]]
  llvm.func @local_index(%w: i64, %bits: i64) -> i64 {
    %one = llvm.mlir.constant(1 : i64) : i64
    %i = llvm.add %w, %one : i64
    %old = schedule.ready.word.load @__talos_aot_model_ingress_v1[%i]
    schedule.ready.word.store %bits, @__talos_aot_model_ingress_v1[%i]
    %above = schedule.ready.word.load @__talos_aot_model_ingress_v1[%i + 1]
    %again = schedule.ready.word.load @__talos_aot_model_ingress_v1[%i]
    %both = llvm.or %old, %above : i64
    %all = llvm.or %both, %again : i64
    llvm.return %all : i64
  }
}
