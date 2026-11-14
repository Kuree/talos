// RUN: talos-opt %s --materialize-native-eval-routes | FileCheck %s --implicit-check-not=latch_destination

// The fast two-state NBA commit runs only when no staged unknown data is
// pending, so it reads the unknown plane as zero and drops its unknown
// writes (IEEE 1800-2023 4.9.4, 10.4.2). A per-site latch destination keeps
// both planes: its selected destination may hold X/Z that the new value
// overwrites, which no fixed dirty bitmap can prove absent. The property is
// consumed here.
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK: schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
// CHECK: schedule.state.store %{{.*}}, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
// CHECK: schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64} : i8
// CHECK: schedule.state.store %{{.*}}, @__talos_state_unknown[1] {alignment = 1 : i64} : i8
// CHECK-LABEL: llvm.func internal @__talos_aot_static_nba_commit_two_state_fast_v1(
// CHECK: schedule.state.load @__talos_state_value[0]
// CHECK: llvm.mlir.zero : i8
// CHECK-NOT: @__talos_state_unknown[0]
// CHECK: schedule.state.store %{{.*}}, @__talos_state_value[0]
// CHECK-NOT: @__talos_state_unknown[0]
// CHECK: schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64} : i8
// CHECK: schedule.state.store %{{.*}}, @__talos_state_unknown[1] {alignment = 1 : i64} : i8
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @dispatch(
// CHECK: llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<8xi8>) : !llvm.array<8 x i8>
  llvm.func @__talos_aot_static_nba_commit_v1(%ctx: !llvm.ptr, %frame: !llvm.ptr, %region: i32, %out: !llvm.ptr) -> i32 {
    %staged = llvm.load %frame {alignment = 1 : i64} : !llvm.ptr -> i8
    %v = schedule.state.load @__talos_state_value[0] {alignment = 1 : i64} : i8
    %u = schedule.state.load @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %nv = llvm.xor %v, %staged : i8
    %nu = llvm.and %u, %staged : i8
    schedule.state.store %nv, @__talos_state_value[0] {alignment = 1 : i64} : i8
    schedule.state.store %nu, @__talos_state_unknown[0] {alignment = 1 : i64} : i8
    %lu = schedule.state.load @__talos_state_unknown[1] {alignment = 1 : i64, latch_destination} : i8
    %nl = llvm.and %lu, %staged : i8
    schedule.state.store %nl, @__talos_state_unknown[1] {alignment = 1 : i64, latch_destination} : i8
    llvm.return %region : i32
  }
  llvm.func @dispatch(%ctx: !llvm.ptr, %frame: !llvm.ptr, %out: !llvm.ptr) -> i32 {
    %region = llvm.mlir.constant(2 : i32) : i32
    %r = llvm.call @__talos_aot_static_nba_commit_v1(%ctx, %frame, %region, %out) {schedule.eval.use_fast_two_state_nba} : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return %r : i32
  }
}
