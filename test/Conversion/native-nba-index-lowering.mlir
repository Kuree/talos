// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))' | FileCheck %s --implicit-check-not=schedule.nba

// An NBA readiness index access becomes a whole-word LLVM access of the index
// global: its address once per block, a byte GEP to a static word or an i64
// GEP by a dynamic one (then by the static words), shared per block, with
// 8-byte alignment. The
// properties are dropped; other dialects' annotations stay with the access.
module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  // CHECK-LABEL: llvm.func @index(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BIT:.*]]: i64, %[[C:.*]]: i1)
  // CHECK-NEXT: %[[DIRTY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1 : !llvm.ptr
  // CHECK-NEXT: %[[LEAF:.*]] = llvm.getelementptr %[[DIRTY]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: %[[OLD:.*]] = llvm.load %[[LEAF]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[NEW:.*]] = llvm.or %[[OLD]], %[[BIT]] : i64
  // CHECK-NEXT: llvm.store %[[NEW]], %[[LEAF]] {alignment = 8 : i64, test.tag} : i64, !llvm.ptr
  // CHECK-NEXT: %[[SUMMARY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_summary_v1 : !llvm.ptr
  // CHECK-NEXT: %[[PAGE:.*]] = llvm.getelementptr %[[SUMMARY]][0] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[PAGE]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[ANY:.*]] = llvm.getelementptr %[[DIRTY]][%[[WORD]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  // CHECK-NEXT: llvm.load %[[ANY]] {alignment = 8 : i64, test.tag} : !llvm.ptr -> i64
  // CHECK-NEXT: %[[NEXT:.*]] = llvm.getelementptr %[[ANY]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.load %[[NEXT]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK-NEXT: llvm.load %[[LEAF]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // CHECK: llvm.cond_br %[[C]]
  // CHECK: ^bb1:
  // CHECK-NEXT: %[[DIRTY2:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1 : !llvm.ptr
  // CHECK-NEXT: %[[LEAF2:.*]] = llvm.getelementptr %[[DIRTY2]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // CHECK-NEXT: llvm.store %[[BIT]], %[[LEAF2]] {alignment = 8 : i64} : i64, !llvm.ptr
  llvm.func @index(%word: i64, %bit: i64, %c: i1) -> i64 {
    %old = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1] {root = 65 : i32}
    %new = llvm.or %old, %bit : i64
    schedule.nba.index.store %new, @__talos_aot_nba_dirty_roots_v1[1] {root = 65 : i32, test.tag}
    %page = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0]
    %any = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%word] {test.tag}
    %next = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%word + 1]
    %again = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1]
    %b = llvm.or %next, %again : i64
    %c2 = llvm.or %any, %b : i64
    %a = llvm.or %page, %c2 : i64
    llvm.cond_br %c, ^bb1, ^bb2
  ^bb1:
    schedule.nba.index.store %bit, @__talos_aot_nba_dirty_roots_v1[1]
    llvm.br ^bb2
  ^bb2:
    llvm.return %a : i64
  }
}
