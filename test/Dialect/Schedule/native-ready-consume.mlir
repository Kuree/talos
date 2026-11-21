// RUN: talos-opt %s --pass-pipeline='builtin.module(convert-native-schedule-actions-to-llvm{coalesce=true},llvm.func(lower-native-ready-words))' -o %t.lowered
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
// CHECK: %[[SET:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK: %[[NEXT:.*]] = arith.andi
// CHECK-NEXT: llvm.store %[[NEXT]], %[[SET]]
// CHECK-NEXT: llvm.call @observe()
// CHECK-NEXT: llvm.return
// A structured single-block region keeps the same straight-line consume.
// CHECK-LABEL: llvm.func @consume_structured(
// CHECK: scf.if
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe
// Multiple actions also pass through ready-region formation. Opaque calls
// observe each consume before the next one begins.
// CHECK-LABEL: llvm.func @consume_global(
// CHECK-NOT: llvm.alloca
// CHECK: %[[BASE:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK: llvm.getelementptr %[[BASE]][32760]
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe()
// CHECK: llvm.getelementptr %[[BASE]][32760]
// CHECK-NOT: cf.cond_br
// CHECK: llvm.call @observe()
// CHECK: llvm.return
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<4161 x i64>
  llvm.func @observe()
  llvm.func @consume(%mask: i64) {
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %mask {capacity = 262144 : i64, consume = true}
    llvm.call @observe() : () -> ()
    llvm.return
  }
  llvm.func @consume_structured(%mask: i64, %guard: i64) {
    %zero = arith.constant 0 : i64
    %active = arith.cmpi ne, %guard, %zero : i64
    scf.if %active {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %mask {capacity = 262144 : i64, consume = true}
    }
    llvm.call @observe() : () -> ()
    llvm.return
  }
  llvm.func @consume_global(%mask: i64) {
    schedule.ready.update @__talos_aot_model_ingress_v1[4095], %mask {capacity = 262144 : i64, consume = true}
    llvm.call @observe() : () -> ()
    schedule.ready.update @__talos_aot_model_ingress_v1[4095], %mask {capacity = 262144 : i64, consume = true}
    llvm.call @observe() : () -> ()
    llvm.return
  }
}
