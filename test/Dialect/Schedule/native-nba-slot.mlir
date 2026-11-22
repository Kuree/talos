// RUN: talos-opt %s | talos-opt | FileCheck %s

// A fixed NBA capture slot global names its site and the field it holds.
// CHECK: llvm.mlir.global internal @offset() {{.*}}schedule.nba.slot = #schedule.nba_slot<site = 3, field = offset>} : i64
// CHECK: llvm.mlir.global internal @value() {{.*}}schedule.nba.slot = #schedule.nba_slot<site = 3, field = value>} : i64
// CHECK: llvm.mlir.global internal @unknown() {{.*}}schedule.nba.slot = #schedule.nba_slot<site = 3, field = unknown>} : i64
// CHECK: llvm.mlir.global internal @valid() {{.*}}schedule.nba.slot = #schedule.nba_slot<site = 3, field = valid>} : i32
// CHECK: llvm.mlir.global internal @transition() {{.*}}schedule.nba.slot = #schedule.nba_slot<site = 4294967296, field = transition>} : !llvm.array<4 x i64>
module {
  llvm.mlir.global internal @offset() {schedule.nba.slot = #schedule.nba_slot<site = 3, field = offset>} : i64
  llvm.mlir.global internal @value() {schedule.nba.slot = #schedule.nba_slot<site = 3, field = value>} : i64
  llvm.mlir.global internal @unknown() {schedule.nba.slot = #schedule.nba_slot<site = 3, field = unknown>} : i64
  llvm.mlir.global internal @valid() {schedule.nba.slot = #schedule.nba_slot<site = 3, field = valid>} : i32
  llvm.mlir.global internal @transition() {schedule.nba.slot = #schedule.nba_slot<site = 4294967296, field = transition>} : !llvm.array<4 x i64>
}
