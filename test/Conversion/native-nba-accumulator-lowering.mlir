// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-state-access))' | FileCheck %s --check-prefix=FOUR --implicit-check-not=schedule.nba
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(lower-native-state-access{two-state=true}))' | FileCheck %s --check-prefix=TWO --implicit-check-not=schedule.nba

// A typed accumulator field access becomes a byte GEP of its record to the
// field's offset in the record layout, and an LLVM access of the same
// alignment. The four-state record is talos_rt_generated_nba_accumulator_256
// (value 0, unknown 32, write_mask 64, valid 96, exec_region 100, transient
// 104); the two-state record omits the unknown field and closes its hole. A
// field address is taken once per block, at its first use; other dialects'
// annotations stay with the access.
module {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  // FOUR-LABEL: llvm.func @fields(
  // FOUR-SAME: %[[V:.*]]: i64, %[[TABLE:.*]]: !llvm.ptr)
  // FOUR-NEXT: %[[R:.*]] = llvm.mlir.addressof @acc : !llvm.ptr
  // FOUR-NEXT: %[[VALUE:.*]] = llvm.getelementptr %[[R]][8] : (!llvm.ptr) -> !llvm.ptr, i8
  // FOUR-NEXT: %[[OLD:.*]] = llvm.load %[[VALUE]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // FOUR-NEXT: %[[NEW:.*]] = llvm.or %[[OLD]], %[[V]] : i64
  // FOUR-NEXT: llvm.store %[[NEW]], %[[VALUE]] {alignment = 8 : i64, test.tag} : i64, !llvm.ptr
  // FOUR-NEXT: %[[MASK:.*]] = llvm.getelementptr %[[R]][64] : (!llvm.ptr) -> !llvm.ptr, i8
  // FOUR-NEXT: llvm.load %[[MASK]] {alignment = 8 : i64} : !llvm.ptr -> i64
  // FOUR-NEXT: %[[VALID:.*]] = llvm.getelementptr %[[R]][96] : (!llvm.ptr) -> !llvm.ptr, i8
  // FOUR-NEXT: llvm.load %[[VALID]] {alignment = 4 : i64} : !llvm.ptr -> i32
  // FOUR-NEXT: %[[REGION:.*]] = llvm.getelementptr %[[TABLE]][100] : (!llvm.ptr) -> !llvm.ptr, i8
  // FOUR-NEXT: llvm.load %[[REGION]] {alignment = 4 : i64} : !llvm.ptr -> i32
  // FOUR-NEXT: %[[TRANSIENT:.*]] = llvm.getelementptr %[[TABLE]][112] : (!llvm.ptr) -> !llvm.ptr, i8
  // FOUR-NEXT: llvm.store %[[V]], %[[TRANSIENT]] {alignment = 8 : i64} : i64, !llvm.ptr
  // TWO-LABEL: llvm.func @fields(
  // TWO: llvm.getelementptr %{{.*}}[8] : (!llvm.ptr) -> !llvm.ptr, i8
  // TWO: llvm.getelementptr %{{.*}}[32] : (!llvm.ptr) -> !llvm.ptr, i8
  // TWO: llvm.getelementptr %{{.*}}[64] : (!llvm.ptr) -> !llvm.ptr, i8
  // TWO: llvm.getelementptr %{{.*}}[68] : (!llvm.ptr) -> !llvm.ptr, i8
  // TWO: llvm.getelementptr %{{.*}}[80] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.func @fields(%v: i64, %table: !llvm.ptr) -> i64 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    %old = schedule.nba.acc.load %r[value + 8] {alignment = 8 : i64} : i64
    %new = llvm.or %old, %v : i64
    schedule.nba.acc.store %new, %r[value + 8] {alignment = 8 : i64, test.tag} : i64
    %mask = schedule.nba.acc.load %r[write_mask] {alignment = 8 : i64, at_commit} : i64
    %valid = schedule.nba.acc.load %r[valid] {alignment = 4 : i64, pending_root = 0 : i32} : i32
    %region = schedule.nba.acc.load %table[exec_region] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %v, %table[transient + 8] {alignment = 8 : i64} : i64
    %flags = llvm.add %valid, %region : i32
    %wide = llvm.zext %flags : i32 to i64
    %sum = llvm.add %mask, %wide : i64
    llvm.return %sum : i64
  }
  // Field addresses are shared within a block, per record and offset only.
  // FOUR-LABEL: llvm.func @blocks(
  // FOUR-SAME: %[[C:.*]]: i1, %[[X:.*]]: i64)
  // FOUR: %[[A:.*]] = llvm.mlir.addressof @acc : !llvm.ptr
  // FOUR: %[[B:.*]] = llvm.mlir.addressof @other : !llvm.ptr
  // FOUR: %[[AMASK:.*]] = llvm.getelementptr %[[A]][64]
  // FOUR-NEXT: llvm.store %[[X]], %[[AMASK]]
  // FOUR-NEXT: %[[BMASK:.*]] = llvm.getelementptr %[[B]][64]
  // FOUR-NEXT: llvm.store %[[X]], %[[BMASK]]
  // FOUR-NEXT: llvm.store %[[X]], %[[AMASK]]
  // FOUR-NEXT: llvm.cond_br %[[C]]
  // FOUR: ^bb1:
  // FOUR-NEXT: %[[AMASK2:.*]] = llvm.getelementptr %[[A]][64]
  // FOUR-NEXT: llvm.store %[[X]], %[[AMASK2]]
  llvm.mlir.global internal @other(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.func @blocks(%c: i1, %x: i64) {
    %a = schedule.nba.acc.address @acc : !llvm.ptr
    %b = schedule.nba.acc.address @other : !llvm.ptr
    schedule.nba.acc.store %x, %a[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %x, %b[write_mask] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %x, %a[write_mask] {alignment = 8 : i64} : i64
    llvm.cond_br %c, ^bb1, ^bb2
  ^bb1:
    schedule.nba.acc.store %x, %a[write_mask] {alignment = 8 : i64} : i64
    llvm.br ^bb2
  ^bb2:
    llvm.return
  }
}
