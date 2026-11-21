// RUN: talos -emit-slang %s -o %t.slang
// RUN: talos-opt %t.slang --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.9.4, 10.4.2, 11.5.1: reconstructing a scalar capture
// from the static NBA ABI must retain the captured unknown bit. Position
// value and unknown with the same shift and mask, then mark the root before
// the generated merge so a value-only barrier cannot discard X/Z.
// CHECK-LABEL: llvm.func @{{.*}}.__talos_eval_body_0.__talos_two_state_0(
// CHECK-DAG: %[[ONE:.*]] = llvm.mlir.constant(1 : i64)
// CHECK-DAG: %[[TRUE:.*]] = llvm.mlir.constant(1 : i8)
// CHECK-DAG: %[[ALL_ONES:.*]] = llvm.mlir.constant(-1 : i64)
// CHECK-DAG: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// CHECK-DAG: %[[FALLBACK:.*]] = llvm.mlir.addressof @__talos_eval_step_four_state_fallback_v1
// CHECK-DAG: %[[TAINT:.*]] = llvm.mlir.addressof @__talos_eval_step_four_state_nba_roots_v1
// CHECK-DAG: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_0
// CHECK: %[[VALUE_BIT:.*]] = llvm.load %{{.*}} {{.*}} : !llvm.ptr -> i1
// CHECK-NEXT: %[[VALUE:.*]] = llvm.zext %[[VALUE_BIT]] : i1 to i64
// CHECK: %[[UNKNOWN_BIT:.*]] = llvm.load %{{.*}} {{.*}} : !llvm.ptr -> i1
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.zext %[[UNKNOWN_BIT]] : i1 to i64
// CHECK: %[[VALUE_SELECTED:.*]] = llvm.lshr %[[VALUE]], %[[SOURCE:.*]] : i64
// CHECK-NEXT: %[[VALUE_POSITIONED:.*]] = llvm.shl %[[VALUE_SELECTED]], %[[DEST:.*]] : i64
// CHECK-NEXT: %[[VALUE_MASKED:.*]] = llvm.and %[[VALUE_POSITIONED]], %[[MASK:.*]] : i64
// CHECK: %[[UNKNOWN_SELECTED:.*]] = llvm.lshr %[[UNKNOWN]], %[[SOURCE]] : i64
// CHECK-NEXT: %[[UNKNOWN_POSITIONED:.*]] = llvm.shl %[[UNKNOWN_SELECTED]], %[[DEST]] : i64
// CHECK-NEXT: %[[UNKNOWN_MASKED:.*]] = llvm.and %[[UNKNOWN_POSITIONED]], %[[MASK]] : i64
// CHECK-NEXT: %[[HAS_XZ:.*]] = llvm.icmp "ne" %[[UNKNOWN_MASKED]], %[[ZERO]] : i64
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
// CHECK-NEXT: %[[MERGED_VALUE:.*]] = llvm.or %[[KEPT_VALUE]], %[[VALUE_MASKED]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_VALUE]], %[[ACC]]
// CHECK-NEXT: %[[UNKNOWN_ADDR:.*]] = llvm.getelementptr %[[ACC]][32]
// CHECK-NEXT: %[[OLD_UNKNOWN:.*]] = llvm.load %[[UNKNOWN_ADDR]]
// CHECK-NEXT: %[[KEPT_UNKNOWN:.*]] = llvm.and %[[OLD_UNKNOWN]], %[[KEEP]] : i64
// CHECK-NEXT: %[[MERGED_UNKNOWN:.*]] = llvm.or %[[KEPT_UNKNOWN]], %[[UNKNOWN_MASKED]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_UNKNOWN]], %[[UNKNOWN_ADDR]]

module top;
  bit clk;
  logic [1:0] en;
  logic signed [63:0] idx, jdx, captured_idx;
  logic [66:0] d = 0, e = 67'b1z, scratch = 0;
  logic [9:10] q, r;
  always #5 clk = !clk;
  always @(posedge clk) begin
    captured_idx = jdx;
    scratch = d;
    if (en[0]) q[captured_idx] <= scratch[0:0];
    if (en[1]) q <= e[1:0];
    captured_idx = idx;
    scratch = d;
    if (en[0]) q[captured_idx +: 64] <= scratch[63:0];
    captured_idx = 'x;
    scratch = 'x;
  end
  always @(posedge clk) r <= q;
  initial #7 $display("%b %b", q, r);
endmodule
