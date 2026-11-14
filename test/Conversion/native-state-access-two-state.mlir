// RUN: talos-opt %s --materialize-native-eval-transactions --canonicalize | FileCheck %s --implicit-check-not=@__talos_state_unknown

// A two-state build has no unknown plane (IEEE 1800-2023 6.11.2: two-state
// values hold no X or Z): its reads are zero, its writes vanish, and a
// pointer into it becomes null rather than an address of a missing global.
// A copy out of a window of it fills its destination with zeros; a copy or
// fill into one vanishes. The X/Z plane of retained continuous contributions
// is zero likewise.
// CHECK-LABEL: llvm.func @access(
// CHECK-SAME: %[[V:.*]]: i8, %{{.*}}: i64, %[[LOCAL:.*]]: !llvm.ptr)
// CHECK-DAG: %[[ZERO:.*]] = llvm.mlir.zero : i8
// CHECK-DAG: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NOT: llvm.getelementptr
// CHECK: schedule.state.store %[[V]], @__talos_state_value[0] {alignment = 1 : i64} : i8
// CHECK-NEXT: llvm.call @use(%[[NULL]])
// CHECK-NEXT: "llvm.intr.memset"(%[[LOCAL]], %[[ZERO]], %{{.*}})
// CHECK-NOT: llvm.intr.mem
// CHECK-NOT: __talos_continuous_unknown
// CHECK: llvm.return %[[ZERO]] : i8
module attributes {native.two_state} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global external @__talos_continuous_unknown() : !llvm.ptr
  llvm.func @use(!llvm.ptr)
  llvm.func @access(%v: i8, %d: i64, %local: !llvm.ptr) -> i8 {
    %u = schedule.state.load @__talos_state_unknown[%d + 1] {alignment = 1 : i64} : i8
    schedule.state.store %v, @__talos_state_unknown[2] {alignment = 1 : i64} : i8
    schedule.state.store %v, @__talos_state_value[0] {alignment = 1 : i64} : i8
    %p = schedule.state.window_address @__talos_state_unknown[%d] : !llvm.ptr
    llvm.call @use(%p) : (!llvm.ptr) -> ()
    %n = llvm.mlir.constant(4 : i64) : i64
    %from = schedule.state.window_address @__talos_state_unknown[%d + 4] : !llvm.ptr
    "llvm.intr.memcpy"(%local, %from, %n) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %into = schedule.state.window_address @__talos_state_unknown[4] : !llvm.ptr
    "llvm.intr.memcpy"(%into, %local, %n) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    "llvm.intr.memset"(%into, %v, %n) <{isVolatile = false}> : (!llvm.ptr, i8, i64) -> ()
    schedule.state.store %v, @__talos_continuous_unknown[1] {alignment = 1 : i64} : i8
    %cw = schedule.state.window_address @__talos_continuous_unknown[0] : !llvm.ptr
    "llvm.intr.memcpy"(%cw, %local, %n) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %cu = schedule.state.load @__talos_continuous_unknown[1] {alignment = 1 : i64} : i8
    %su = llvm.or %u, %cu : i8
    llvm.return %su : i8
  }
}
