// RUN: talos-opt %s --split-input-file --materialize-native-eval-transactions | FileCheck %s --implicit-check-not=schedule.nba.slot

// A two-state executable simulates every variable as a 2-state type, which
// holds no X or Z (IEEE 1800-2023 6.11.2), so it has no X/Z words: the fixed
// NBA capture slot globals marked as X/Z fields go with the unknown plane.
// Their loads read 0, their stores vanish and a slot table holds null in
// their place. The mark, not the name, selects them: a same-named global
// without one stays.
// CHECK-LABEL: module attributes {native.two_state}
// CHECK-NEXT: llvm.mlir.global internal @__talos_eval_nba_value_3()
// CHECK-NOT: @__talos_eval_nba_unknown_3
// CHECK: llvm.mlir.global internal @__talos_eval_nba_unknown_9()
// CHECK-LABEL: llvm.mlir.global internal constant @slots()
// CHECK-NEXT: %[[TABLE:.*]] = llvm.mlir.undef
// CHECK-NEXT: %[[VALUE:.*]] = llvm.mlir.addressof @__talos_eval_nba_value_3
// CHECK-NEXT: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: %[[FIRST:.*]] = llvm.insertvalue %[[VALUE]], %[[TABLE]][0]
// CHECK-NEXT: llvm.insertvalue %[[NULL]], %[[FIRST]][1]
// CHECK-LABEL: llvm.func @stage(
// CHECK-SAME: %[[WORD:.*]]: i64)
// CHECK-NEXT: llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: %[[KEPT:.*]] = llvm.mlir.addressof @__talos_eval_nba_unknown_9
// CHECK-NEXT: llvm.store %[[WORD]], %[[KEPT]]
// CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.zero : i64
// CHECK-NEXT: llvm.return %[[ZERO]] : i64
module attributes {native.two_state} {
  llvm.mlir.global internal @__talos_eval_nba_value_3() {alignment = 8 : i64, schedule.nba.slot = #schedule.nba_slot<site = 3, field = value>} : i64 {
    %zero = llvm.mlir.zero : i64
    llvm.return %zero : i64
  }
  llvm.mlir.global internal @__talos_eval_nba_unknown_3() {alignment = 8 : i64, schedule.nba.slot = #schedule.nba_slot<site = 3, field = unknown>} : i64 {
    %zero = llvm.mlir.zero : i64
    llvm.return %zero : i64
  }
  llvm.mlir.global internal @__talos_eval_nba_unknown_9() {alignment = 8 : i64} : i64 {
    %zero = llvm.mlir.zero : i64
    llvm.return %zero : i64
  }
  llvm.mlir.global internal constant @slots() {alignment = 8 : i64} : !llvm.struct<(ptr, ptr)> {
    %table = llvm.mlir.undef : !llvm.struct<(ptr, ptr)>
    %value = llvm.mlir.addressof @__talos_eval_nba_value_3 : !llvm.ptr
    %unknown = llvm.mlir.addressof @__talos_eval_nba_unknown_3 : !llvm.ptr
    %first = llvm.insertvalue %value, %table[0] : !llvm.struct<(ptr, ptr)>
    %both = llvm.insertvalue %unknown, %first[1] : !llvm.struct<(ptr, ptr)>
    llvm.return %both : !llvm.struct<(ptr, ptr)>
  }
  llvm.func @stage(%word: i64) -> i64 {
    %unknown = llvm.mlir.addressof @__talos_eval_nba_unknown_3 : !llvm.ptr
    llvm.store %word, %unknown {alignment = 8 : i64} : i64, !llvm.ptr
    %kept = llvm.mlir.addressof @__talos_eval_nba_unknown_9 : !llvm.ptr
    llvm.store %word, %kept {alignment = 8 : i64} : i64, !llvm.ptr
    %staged = llvm.load %unknown {alignment = 8 : i64} : !llvm.ptr -> i64
    llvm.return %staged : i64
  }
}

// -----

// A four-state executable keeps every slot global; only the marks go.
// CHECK-LABEL: module {
// CHECK: llvm.mlir.global internal @__talos_eval_nba_unknown_3() {addr_space = 0 : i32, alignment = 8 : i64} : i64
// CHECK-LABEL: llvm.func @stage(
// CHECK: llvm.store %{{.*}}, %{{.*}} {alignment = 8 : i64} : i64, !llvm.ptr
module {
  llvm.mlir.global internal @__talos_eval_nba_unknown_3() {alignment = 8 : i64, schedule.nba.slot = #schedule.nba_slot<site = 3, field = unknown>} : i64 {
    %zero = llvm.mlir.zero : i64
    llvm.return %zero : i64
  }
  llvm.func @stage(%word: i64) {
    %unknown = llvm.mlir.addressof @__talos_eval_nba_unknown_3 : !llvm.ptr
    llvm.store %word, %unknown {alignment = 8 : i64} : i64, !llvm.ptr
    llvm.return
  }
}
