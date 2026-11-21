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
// The trap path keeps the CFG out of ready-region formation, so straight-line
// batches lower these actions.
// CHECK-LABEL: llvm.func @exercise
// CHECK-NOT: schedule.ready
// CHECK-COUNT-6: llvm.store
// CHECK-NOT: llvm.store
// CHECK: llvm.call @observe
// CHECK-NOT: schedule.ready
// CHECK: llvm.return
module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<4161 x i64>
  llvm.func @observe(!llvm.ptr)
  llvm.func @exercise(%a: i64, %b: i64) {
    %base = llvm.mlir.addressof @__talos_aot_model_ingress_v1 : !llvm.ptr
    %zero = arith.constant 0 : i64
    %all = arith.constant -1 : i64
    schedule.ready.update @__talos_aot_model_ingress_v1[0], %a {capacity = 262144 : i64, consume = false}
    schedule.ready.update @__talos_aot_model_ingress_v1[63], %b {capacity = 262144 : i64, consume = false}
    schedule.ready.update @__talos_aot_model_ingress_v1[64], %a {capacity = 262144 : i64, consume = true}
    schedule.ready.update @__talos_aot_model_ingress_v1[4095], %all {capacity = 262144 : i64, consume = true}
    schedule.ready.commit @__talos_aot_model_ingress_v1[0], %a, %b {capacity = 262144 : i64}
    llvm.call @observe(%base) : (!llvm.ptr) -> ()
    schedule.ready.update @__talos_aot_model_ingress_v1[63], %all {capacity = 262144 : i64, consume = true}
    schedule.ready.update @__talos_aot_model_ingress_v1[64], %zero {capacity = 262144 : i64, consume = false}
    schedule.ready.update @__talos_aot_model_ingress_v1[4095], %a {capacity = 262144 : i64, consume = false}
    %trap = arith.cmpi ult, %a, %zero : i64
    cf.cond_br %trap, ^trap, ^done
  ^trap:
    llvm.unreachable
  ^done:
    llvm.return
  }
}
