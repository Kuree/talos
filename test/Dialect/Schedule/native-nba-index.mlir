// RUN: talos-opt %s | talos-opt | FileCheck %s

// Words of the NBA readiness index are read and written whole, at a static
// word or a dynamic one. A root's own test or mark names the root; a
// runtime-held capture's mark keeps the root canonical; a generated capture's
// mark certifies its target.
module {
  llvm.mlir.global internal @__talos_aot_nba_dirty_roots_v1(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_aot_nba_dirty_summary_v1(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  // CHECK-LABEL: llvm.func @index(
  // CHECK-SAME: %[[WORD:.*]]: i64, %[[BITS:.*]]: i64)
  llvm.func @index(%word: i64, %bits: i64) -> i64 {
    // CHECK: schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1] {root = 65 : i32}
    %own = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[1] {root = 65 : i32}
    // CHECK: schedule.nba.index.store %[[BITS]], @__talos_aot_nba_dirty_roots_v1[1] {capture = array<i64: 65, 3, 8, 255, 2, 7>, root = 65 : i32}
    schedule.nba.index.store %bits, @__talos_aot_nba_dirty_roots_v1[1] {capture = array<i64: 65, 3, 8, 255, 2, 7>, root = 65 : i32}
    // CHECK: schedule.nba.index.store %[[BITS]], @__talos_aot_nba_dirty_summary_v1[0] {canonical_capture, root = 65 : i32}
    schedule.nba.index.store %bits, @__talos_aot_nba_dirty_summary_v1[0] {canonical_capture, root = 65 : i32}
    // CHECK: schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%[[WORD]]]
    %any = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%word]
    // CHECK: schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%[[WORD]] + 1]
    %next = schedule.nba.index.load @__talos_aot_nba_dirty_roots_v1[%word + 1]
    // CHECK: schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0] {owner = 2 : i32}
    %page = schedule.nba.index.load @__talos_aot_nba_dirty_summary_v1[0] {owner = 2 : i32}
    %own2 = llvm.or %own, %next : i64
    %a = llvm.or %own2, %any : i64
    %b = llvm.or %a, %page : i64
    llvm.return %b : i64
  }
}
