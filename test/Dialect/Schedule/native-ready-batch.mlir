// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm -o %t.lowered
// RUN: FileCheck %s < %t.lowered
// RUN: %llvm_dist/bin/mlir-opt %t.lowered --convert-arith-to-llvm --convert-cf-to-llvm | talos-translate --mlir-to-llvmir > %t.ll
// RUN: %llvm_dist/bin/clang -O0 %t.ll %S/Inputs/native-ready-batch.c -o %t.o0
// RUN: %t.o0
// RUN: %llvm_dist/bin/clang -O3 %t.ll %S/Inputs/native-ready-batch.c -o %t.o3
// RUN: %t.o3

// Multiple leaves share dirty words. Dynamic masks, repeated leaf updates and
// consumes write each leaf and dirty word once: a dirty bit is set for every
// leaf that may have received an add, and consumes leave dirty bits alone.
// A callback sees all pending work; its changes survive the following batch.
// CHECK-LABEL: llvm.func @exercise
// CHECK-NOT: schedule.ready
// CHECK-COUNT-6: llvm.store
// CHECK-NOT: llvm.store
// CHECK: llvm.call @observe
// CHECK-NOT: schedule.ready
// CHECK: llvm.return
module {
  llvm.func @observe(!llvm.ptr)
  llvm.func @exercise(%base: !llvm.ptr, %a: i64, %b: i64) {
    %zero = arith.constant 0 : i64
    %all = arith.constant -1 : i64
    schedule.ready.update %base, %a {capacity = 262144 : i64, word = 0 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    schedule.ready.update %base, %b {capacity = 262144 : i64, word = 63 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    schedule.ready.update %base, %a {capacity = 262144 : i64, word = 64 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    schedule.ready.update %base, %all {capacity = 262144 : i64, word = 4095 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    schedule.ready.commit %base, %a, %b {capacity = 262144 : i64, word = 0 : i64} : (!llvm.ptr, i64, i64) -> ()
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    schedule.ready.update %base, %all {capacity = 262144 : i64, word = 63 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    schedule.ready.update %base, %zero {capacity = 262144 : i64, word = 64 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    schedule.ready.update %base, %a {capacity = 262144 : i64, word = 4095 : i64, consume = false} : (!llvm.ptr, i64) -> ()
    llvm.return
  }
}
