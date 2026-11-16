// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3 clocked-kernels=off' | FileCheck %s --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.9.4, 10.4.2, 11.5.1: clip in the full payload type
// before truncation, including negative indices selecting bits above bit 63.
// Use the same positioned mask for both planes, test captured unknown bits
// before merging, and preserve bits outside the current write mask.
// CHECK-LABEL: llvm.func @{{.*}}.__talos_eval_body_0.__talos_two_state_0(
// CHECK-DAG: %[[TRUE:.*]] = llvm.mlir.constant(1 : i8)
// CHECK-DAG: %[[FALLBACK:.*]] = llvm.mlir.addressof @__talos_eval_step_four_state_fallback_v1
// CHECK-DAG: %[[TAINT:.*]] = llvm.mlir.addressof @__talos_eval_step_four_state_nba_roots_v1
// CHECK-DAG: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// CHECK-DAG: %[[ALL_ONES:.*]] = llvm.mlir.constant(-1 : i64)
// CHECK-DAG: %[[ONE:.*]] = llvm.mlir.constant(1 : i64)
// CHECK-DAG: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_0
// CHECK: %[[SHIFT:.*]] = llvm.zext %{{.*}} : i64 to i81
// CHECK-NEXT: %[[WIDE_VALUE:.*]] = llvm.lshr %{{.*}}, %[[SHIFT]] : i81
// CHECK-NEXT: %[[VALUE:.*]] = llvm.trunc %[[WIDE_VALUE]] : i81 to i64
// CHECK-NEXT: %[[POSITIONED_VALUE:.*]] = llvm.shl %[[VALUE]], %[[DEST:.*]] : i64
// CHECK-NEXT: %[[MASKED_VALUE:.*]] = llvm.and %[[POSITIONED_VALUE]], %[[MASK:.*]] : i64
// CHECK: %[[WIDE_UNKNOWN:.*]] = llvm.lshr %{{.*}}, %[[SHIFT]] : i81
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.trunc %[[WIDE_UNKNOWN]] : i81 to i64
// CHECK-NEXT: %[[POSITIONED_UNKNOWN:.*]] = llvm.shl %[[UNKNOWN]], %[[DEST]] : i64
// CHECK-NEXT: %[[MASKED_UNKNOWN:.*]] = llvm.and %[[POSITIONED_UNKNOWN]], %[[MASK]] : i64
// CHECK-NEXT: %[[HAS_XZ:.*]] = llvm.icmp "ne" %[[MASKED_UNKNOWN]], %[[ZERO]] : i64
// CHECK-NEXT: llvm.cond_br %[[HAS_XZ]], ^[[MARK:bb[0-9]+]], ^[[MERGE:bb[0-9]+]]
// CHECK: ^[[MARK]]:
// CHECK: llvm.store %[[TRUE]], %[[FALLBACK]] {{.*}} : i8, !llvm.ptr
// CHECK: %[[OLD_TAINT:.*]] = llvm.load %[[TAINT]]
// CHECK-NEXT: %[[MARKED:.*]] = llvm.or %[[OLD_TAINT]], %[[ONE]] : i64
// CHECK-NEXT: llvm.store %[[MARKED]], %[[TAINT]]
// CHECK: ^[[MERGE]]:
// CHECK-NEXT: %[[OLD_VALUE:.*]] = llvm.load %[[ACC]]
// CHECK-NEXT: %[[KEEP:.*]] = llvm.xor %[[MASK]], %[[ALL_ONES]] : i64
// CHECK-NEXT: %[[KEPT_VALUE:.*]] = llvm.and %[[OLD_VALUE]], %[[KEEP]] : i64
// CHECK-NEXT: %[[MERGED_VALUE:.*]] = llvm.or %[[KEPT_VALUE]], %[[MASKED_VALUE]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_VALUE]], %[[ACC]]
// CHECK-NEXT: %[[UNKNOWN_ADDR:.*]] = llvm.getelementptr %[[ACC]][32]
// CHECK-NEXT: %[[OLD_UNKNOWN:.*]] = llvm.load %[[UNKNOWN_ADDR]]
// CHECK-NEXT: %[[KEPT_UNKNOWN:.*]] = llvm.and %[[OLD_UNKNOWN]], %[[KEEP]] : i64
// CHECK-NEXT: %[[MERGED_UNKNOWN:.*]] = llvm.or %[[KEPT_UNKNOWN]], %[[MASKED_UNKNOWN]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_UNKNOWN]], %[[UNKNOWN_ADDR]]

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic [2:0] en = 3'b111;
  logic signed [63:0] idx = 0, captured_idx = 0;
  logic [80:0] d = 81'h15555, scratch = 0;
  logic [16:0] q = 0, r = 0;
  always #5 clk = !clk;
  always @(posedge clk) begin
    captured_idx = idx;
    scratch = d;
    if (en[1]) q[captured_idx +: 81] <= scratch;
    captured_idx = 'x;
    scratch = 'x;
  end
  always @(posedge clk) r <= q;
endmodule
