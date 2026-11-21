// RUN: talos-opt %s | talos-opt | FileCheck %s

// A generated NBA accumulator record is addressed by name, or read from a
// table of records; its fields are read and written by typed accesses at a
// byte offset inside the field.
module {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  // CHECK-LABEL: llvm.func @fields(
  // CHECK-SAME: %[[V:.*]]: i64, %[[LANE:.*]]: i32, %[[TABLE:.*]]: !llvm.ptr)
  llvm.func @fields(%v: i64, %lane: i32, %table: !llvm.ptr) -> i32 {
    // CHECK: %[[R:.*]] = schedule.nba.acc.address @acc : !llvm.ptr
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    // CHECK: schedule.nba.acc.store %[[V]], %[[R]][value + 8] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %v, %r[value + 8] {alignment = 8 : i64} : i64
    // CHECK: schedule.nba.acc.store %[[LANE]], %[[R]][unknown + 28] {alignment = 4 : i64} : i32
    schedule.nba.acc.store %lane, %r[unknown + 28] {alignment = 4 : i64} : i32
    // CHECK: schedule.nba.acc.load %[[R]][write_mask] {alignment = 8 : i64, at_commit} : i64
    %m = schedule.nba.acc.load %r[write_mask] {alignment = 8 : i64, at_commit} : i64
    // CHECK: schedule.nba.acc.load %[[R]][valid] {alignment = 4 : i64, pending_root = 3 : i32} : i32
    %p = schedule.nba.acc.load %r[valid] {alignment = 4 : i64, pending_root = 3 : i32} : i32
    // CHECK: schedule.nba.acc.load %[[TABLE]][exec_region] {alignment = 4 : i64, owner = 2 : i32} : i32
    %e = schedule.nba.acc.load %table[exec_region] {alignment = 4 : i64, owner = 2 : i32} : i32
    // CHECK: schedule.nba.acc.store %[[V]], %[[TABLE]][transient + 24] {alignment = 8 : i64} : i64
    schedule.nba.acc.store %v, %table[transient + 24] {alignment = 8 : i64} : i64
    %s = llvm.add %p, %e : i32
    llvm.return %s : i32
  }
}
