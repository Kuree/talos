// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-mask-words))' | FileCheck %s --implicit-check-not=schedule.mask

// An eval mask word access becomes a whole-word LLVM access of the mask's
// global with 8-byte alignment, addressed as ready set words are: the mask's
// address once per function, at the start of its entry block in the order of
// first use, then word 0 at that address, a byte GEP to another static word,
// or an i64 GEP by a dynamic word, once per block, and a byte GEP to its
// static words. An owner becomes the access's group-owner tag; other
// dialects' annotations stay with the access. A raw address of a mask stays:
// a mask's words may escape, unlike a ready set's.
module {
  llvm.mlir.global internal @__talos_eval_promotion_pending_mask_v1(dense<0> : tensor<2xi64>) : !llvm.array<2 x i64>
  llvm.mlir.global internal @__talos_eval_step_four_state_nba_roots_v1(dense<0> : tensor<3xi64>) : !llvm.array<3 x i64>
  // CHECK-LABEL: llvm.func @words(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BITS:.*]]: i64, %[[C:.*]]: i1)
  // CHECK-NEXT: %[[PENDING:.*]] = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
  // CHECK-NEXT: %[[ROOTS:.*]] = llvm.mlir.addressof @__talos_eval_step_four_state_nba_roots_v1 : !llvm.ptr
  // CHECK-NEXT: %[[FIRST:.*]] = llvm.load %[[PENDING]] {alignment = 8 : i64, schedule.eval.group_owner = 3 : i32} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[SECOND:.*]] = llvm.getelementptr %[[PENDING]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[SECOND]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: llvm.cond_br %[[C]]
  // CHECK: ^bb1:
  // CHECK-NEXT: %[[AT:.*]] = llvm.getelementptr %[[ROOTS]][%[[WORD]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: %[[OLD:.*]] = llvm.load %[[AT]] {alignment = 8 : i64, test.tag} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[NEW:.*]] = llvm.or %[[OLD]], %[[BITS]] : i64
  // CHECK-NEXT: llvm.store %[[NEW]], %[[AT]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK-NEXT: %[[BASE:.*]] = llvm.getelementptr %[[ROOTS]][%[[WORD]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: %[[UP:.*]] = llvm.getelementptr %[[BASE]][16] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %[[BITS]], %[[UP]] {alignment = 8 : i64} : i64, !llvm.ptr
  // CHECK: ^bb2:
  // CHECK-NEXT: %[[RAW:.*]] = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
  // CHECK-NEXT: llvm.call @certify(%[[RAW]])
  // CHECK-NEXT: llvm.store %[[BITS]], %[[PENDING]] {alignment = 8 : i64} : i64, !llvm.ptr
  llvm.func @certify(!llvm.ptr)
  llvm.func @words(%word: i64, %bits: i64, %c: i1) -> i64 {
    %first = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[0] {owner = 3 : i32}
    %second = schedule.mask.load @__talos_eval_promotion_pending_mask_v1[1]
    llvm.cond_br %c, ^dynamic, ^done
  ^dynamic:
    %old = schedule.mask.load @__talos_eval_step_four_state_nba_roots_v1[%word] {test.tag}
    %new = llvm.or %old, %bits : i64
    schedule.mask.store %new, @__talos_eval_step_four_state_nba_roots_v1[%word]
    schedule.mask.store %bits, @__talos_eval_step_four_state_nba_roots_v1[%word + 2]
    llvm.br ^done
  ^done:
    %raw = llvm.mlir.addressof @__talos_eval_promotion_pending_mask_v1 : !llvm.ptr
    llvm.call @certify(%raw) : (!llvm.ptr) -> ()
    schedule.mask.store %bits, @__talos_eval_promotion_pending_mask_v1[0]
    %any = llvm.or %first, %second : i64
    llvm.return %any : i64
  }
}
