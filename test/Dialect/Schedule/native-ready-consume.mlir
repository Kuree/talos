// RUN: talos-opt %s --convert-native-schedule-actions-to-llvm='coalesce=true' -o %t.lowered
// RUN: FileCheck %s < %t.lowered
// RUN: %llvm_dist/bin/mlir-opt %t.lowered --convert-scf-to-cf --convert-arith-to-llvm --convert-cf-to-llvm | talos-translate --mlir-to-llvmir > %t.ll
// RUN: %llvm_dist/bin/clang -O0 %t.ll %S/Inputs/native-ready-consume.c -o %t.o0
// RUN: %t.o0
// RUN: %llvm_dist/bin/clang -O3 %t.ll %S/Inputs/native-ready-consume.c -o %t.o3
// RUN: %t.o3

// Consuming pending work clears only its leaf. Dirty bits are a superset of
// the nonempty children (runtime::DirtyReadySetLayout): only the coordinator's
// sweep clears them, after observing a child empty. An observer after the
// consume sees the leaf and unchanged dirty words (LRM 4.5--4.7).
// CHECK-LABEL: llvm.func @consume(
// CHECK: %[[NEXT:.*]] = arith.andi
// CHECK-NEXT: llvm.store %[[NEXT]], %arg0
// CHECK-NEXT: llvm.call @observe(%arg0)
// CHECK-NEXT: llvm.return
// A structured single-block region keeps the same straight-line consume.
// CHECK-LABEL: llvm.func @consume_structured(
// CHECK: scf.if
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe
// A resolved global with multiple actions also passes through ready-region
// formation. Opaque calls observe each consume before the next one begins.
// CHECK-LABEL: llvm.func @consume_global(
// CHECK-NOT: llvm.alloca
// CHECK: %[[BASE:.*]] = llvm.mlir.addressof @ready
// CHECK: llvm.getelementptr %[[BASE]][32760]
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe(%[[BASE]])
// CHECK: llvm.getelementptr %[[BASE]][32760]
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe(%[[BASE]])
// CHECK: llvm.return
module {
  llvm.mlir.global external @ready() : !llvm.array<4161 x i64>
  llvm.func @observe(!llvm.ptr)
  llvm.func @consume(%base: !llvm.ptr, %mask: i64) {
    schedule.ready.update %base, %mask {capacity = 262144 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    llvm.return
  }
  llvm.func @consume_structured(%base: !llvm.ptr, %mask: i64, %guard: i64) {
    %zero = arith.constant 0 : i64
    %active = arith.cmpi ne, %guard, %zero : i64
    scf.if %active {
      schedule.ready.update %base, %mask {capacity = 262144 : i64, word = 0 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    }
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    llvm.return
  }
  llvm.func @consume_global(%mask: i64) {
    %base = llvm.mlir.addressof @ready : !llvm.ptr
    schedule.ready.update %base, %mask {capacity = 262144 : i64, word = 4095 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    schedule.ready.update %base, %mask {capacity = 262144 : i64, word = 4095 : i64, consume = true} : (!llvm.ptr, i64) -> ()
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    llvm.return
  }
}
