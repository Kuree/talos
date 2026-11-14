// RUN: talos-opt %s --materialize-native-eval-transactions --canonicalize | FileCheck %s --implicit-check-not=@__talos_state_unknown

// A two-state build has no unknown plane (IEEE 1800-2023 6.11.2: two-state
// values hold no X or Z): its reads are zero, its writes vanish, and a
// pointer into it becomes null rather than an address of a missing global.
// CHECK-LABEL: llvm.func @access(
// CHECK-SAME: %[[V:.*]]: i8, %{{.*}}: i64)
// CHECK-DAG: %[[ZERO:.*]] = llvm.mlir.zero : i8
// CHECK-DAG: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NOT: llvm.getelementptr
// CHECK: schedule.state.store %[[V]], @__talos_state_value[0] {alignment = 1 : i64} : i8
// CHECK-NEXT: llvm.call @use(%[[NULL]])
// CHECK-NEXT: llvm.return %[[ZERO]] : i8
module attributes {native.two_state} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @use(!llvm.ptr)
  llvm.func @access(%v: i8, %d: i64) -> i8 {
    %u = schedule.state.load @__talos_state_unknown[%d + 1] {alignment = 1 : i64} : i8
    schedule.state.store %v, @__talos_state_unknown[2] {alignment = 1 : i64} : i8
    schedule.state.store %v, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %base = schedule.state.address @__talos_state_unknown : !llvm.ptr
    %p = llvm.getelementptr %base[%d] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.call @use(%p) : (!llvm.ptr) -> ()
    llvm.return %u : i8
  }
}
