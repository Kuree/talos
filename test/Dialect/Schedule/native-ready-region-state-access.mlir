// RUN: talos-opt %s --pass-pipeline='builtin.module(convert-native-schedule-actions-to-llvm,llvm.func(lower-native-ready-words))' | FileCheck %s

// State accesses never touch a ready set: a typed access names its plane, and
// an LLVM access through a plane's base addresses that plane. Neither ends a
// ready batch, so both updates reach the ready word in one write after them.
// CHECK-LABEL: llvm.func @exercise(
// CHECK: %[[FIRST:.*]] = arith.ori %{{.*}}, %{{.*}} : i64
// CHECK-NEXT: schedule.state.store
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK: llvm.store %{{.*}}, %{{.*}} {alignment = 1 : i64} : i8, !llvm.ptr
// CHECK-NOT: @__talos_aot_model_ingress_v1
// CHECK: %[[BOTH:.*]] = arith.ori %[[FIRST]], %{{.*}} : i64
// CHECK-NEXT: %[[OLD:.*]] = llvm.load %[[READY:.*]] {alignment = 8 : i64} : !llvm.ptr -> i64
// CHECK: %[[NEW:.*]] = arith.ori %[[OLD]], %[[BOTH]] : i64
// CHECK-NEXT: llvm.store %[[NEW]], %[[READY]]
// CHECK-NEXT: llvm.return

module {
  llvm.mlir.global external @__talos_aot_model_ingress_v1() : !llvm.array<1 x i64> {
    %zero = llvm.mlir.zero : !llvm.array<1 x i64>
    llvm.return %zero : !llvm.array<1 x i64>
  }
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @exercise(%v: i8, %d: i64) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 64 : i64, consume = false}
      schedule.state.store %v, @__talos_state_value[1] {alignment = 1 : i64} : i8
      %plane = schedule.state.address @__talos_state_value : !llvm.ptr
      %p = llvm.getelementptr %plane[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store %v, %p {alignment = 1 : i64} : i8, !llvm.ptr
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 64 : i64, consume = false}
      schedule.ready.yield
    }
    llvm.return
  }
}
