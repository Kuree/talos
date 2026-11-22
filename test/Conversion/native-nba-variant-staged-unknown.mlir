// RUN: talos-opt %s --split-input-file --materialize-native-eval-routes | FileCheck %s

// A two-state step stages no X/Z bits, but an accumulator record's X/Z field
// can still hold bits an earlier four-state step staged. The two-state commit
// variants read that field as zero; the four-state source keeps reading it.
// Zero is exact only because the eval dispatch enters a two-state variant
// when no NBA it commits staged X/Z bits, as its guard proves; a commit
// applies the value each NBA staged (IEEE 1800-2023 4.9.4, 10.4.2). This test
// pins the variants' bodies; its @dispatch calls them unguarded. A source
// that reads staged X/Z data has a canonical two-state variant of its own.
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK: schedule.nba.acc.load %{{.*}}[unknown] {alignment = 8 : i64} : i64
// CHECK-LABEL: llvm.func internal @__talos_aot_static_nba_commit_two_state_v1(
// CHECK-NOT: [unknown]
// CHECK: %[[ZERO:.*]] = llvm.mlir.zero : i64
// CHECK-NOT: [unknown]
// CHECK: llvm.and %[[ZERO]], %{{.*}} : i64
// CHECK-LABEL: llvm.func internal @__talos_aot_static_nba_commit_two_state_fast_v1(
// CHECK-NOT: [unknown]
// CHECK: %[[FAST_ZERO:.*]] = llvm.mlir.zero : i64
// CHECK-NOT: [unknown]
// CHECK: llvm.and %[[FAST_ZERO]], %{{.*}} : i64
// CHECK-LABEL: llvm.func @dispatch(
// CHECK: llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(
// CHECK: llvm.call @__talos_aot_static_nba_commit_two_state_v1(
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.func @__talos_aot_static_nba_commit_v1(%ctx: !llvm.ptr, %frame: !llvm.ptr, %region: i32, %out: !llvm.ptr) -> i32 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    %mask = schedule.nba.acc.load %r[write_mask] {alignment = 8 : i64, at_commit} : i64
    %staged = schedule.nba.acc.load %r[unknown] {alignment = 8 : i64} : i64
    %written = llvm.and %staged, %mask : i64
    llvm.store %written, %out {alignment = 8 : i64} : i64, !llvm.ptr
    llvm.return %region : i32
  }
  llvm.func @__talos_aot_static_nba_commit_two_state_fast_v1(!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  llvm.func @__talos_aot_static_nba_commit_two_state_v1(!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  llvm.func @dispatch(%ctx: !llvm.ptr, %frame: !llvm.ptr, %out: !llvm.ptr) -> i32 {
    %region = llvm.mlir.constant(2 : i32) : i32
    %r = llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(%ctx, %frame, %region, %out) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    %c = llvm.call @__talos_aot_static_nba_commit_two_state_v1(%ctx, %frame, %region, %out) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    %s = llvm.add %r, %c : i32
    llvm.return %s : i32
  }
}

// -----

// The canonical two-state variant is defined only for a caller that declared
// it, a caller in the two-state domain; the fast variant always is.
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK: schedule.nba.acc.load %{{.*}}[unknown]
// CHECK-NOT: @__talos_aot_static_nba_commit_two_state_v1
// CHECK-LABEL: llvm.func internal @__talos_aot_static_nba_commit_two_state_fast_v1(
// CHECK-NOT: @__talos_aot_static_nba_commit_two_state_v1
// CHECK-LABEL: llvm.func @dispatch(
// CHECK-NEXT: llvm.mlir.constant(2 : i32)
// CHECK-NEXT: llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.func @__talos_aot_static_nba_commit_v1(%ctx: !llvm.ptr, %frame: !llvm.ptr, %region: i32, %out: !llvm.ptr) -> i32 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    %staged = schedule.nba.acc.load %r[unknown] {alignment = 8 : i64} : i64
    llvm.store %staged, %out {alignment = 8 : i64} : i64, !llvm.ptr
    llvm.return %region : i32
  }
  llvm.func @__talos_aot_static_nba_commit_two_state_fast_v1(!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  llvm.func @dispatch(%ctx: !llvm.ptr, %frame: !llvm.ptr, %out: !llvm.ptr) -> i32 {
    %region = llvm.mlir.constant(2 : i32) : i32
    %r = llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(%ctx, %frame, %region, %out) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return %r : i32
  }
}

// -----

// A source that reads no staged X/Z data equals its canonical two-state
// variant, so that variant's callers call the source and its declaration
// goes.
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK-NOT: @__talos_aot_static_nba_commit_two_state_v1
// CHECK-LABEL: llvm.func @dispatch(
// CHECK-NEXT: %[[REGION:.*]] = llvm.mlir.constant(2 : i32)
// CHECK-NEXT: llvm.call @__talos_aot_static_nba_commit_v1(%{{.*}}, %{{.*}}, %[[REGION]], %{{.*}})
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.mlir.global internal @acc(dense<0> : tensor<136xi8>) : !llvm.array<136 x i8>
  llvm.func @__talos_aot_static_nba_commit_v1(%ctx: !llvm.ptr, %frame: !llvm.ptr, %region: i32, %out: !llvm.ptr) -> i32 {
    %r = schedule.nba.acc.address @acc : !llvm.ptr
    %staged = schedule.nba.acc.load %r[value] {alignment = 8 : i64} : i64
    llvm.store %staged, %out {alignment = 8 : i64} : i64, !llvm.ptr
    llvm.return %region : i32
  }
  llvm.func @__talos_aot_static_nba_commit_two_state_v1(!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  llvm.func @dispatch(%ctx: !llvm.ptr, %frame: !llvm.ptr, %out: !llvm.ptr) -> i32 {
    %region = llvm.mlir.constant(2 : i32) : i32
    %c = llvm.call @__talos_aot_static_nba_commit_two_state_v1(%ctx, %frame, %region, %out) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return %c : i32
  }
}
