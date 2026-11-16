// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3 clocked-kernels=off' | FileCheck %s --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 6.3.1, 10.4.2, 11.5.1: a partial known write leaves
// X/Z outside its mask. A persistent destination certificate must inspect
// the whole root. Per-update recovery may inspect only the current mask;
// its canonicalizing commit must not latch a whole-root certificate.
//
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: %[[FAST:.*]] = llvm.mlir.addressof @__talos_eval_fast_nba_roots_v1
// CHECK: %[[FALSE:.*]] = llvm.mlir.constant(false) : i1
// CHECK: %[[TRUE:.*]] = llvm.mlir.constant(true) : i1
// CHECK: %[[KNOWN:.*]] = llvm.call @__talos_eval_nba_known_v1(%{{[^,]+}}, %[[TRUE]], %[[TRUE]])
// CHECK: %[[WHOLE_KNOWN:.*]] = llvm.call @__talos_eval_nba_known_v1(%{{[^,]+}}, %[[TRUE]], %[[FALSE]])
// CHECK-NEXT: llvm.cond_br %[[WHOLE_KNOWN]] {{.*}}, ^[[LATCH:bb[0-9]+]], ^[[CANONICAL:bb[0-9]+]]
// CHECK: ^[[LATCH]]:
// CHECK: llvm.store %{{.*}}, %[[FAST]]
// CHECK: ^[[CANONICAL]]:
// CHECK-NEXT: llvm.br ^[[CANONICAL_COMMIT:bb[0-9]+]]
// CHECK: ^[[CANONICAL_COMMIT]]:
// CHECK-NOT: llvm.store %{{.*}}, %[[FAST]]
// CHECK: llvm.call @__talos_aot_static_nba_commit_two_state_v1(
// CHECK-NEXT: llvm.br
//
// CHECK-LABEL: llvm.func internal @__talos_eval_nba_known_v1(
// CHECK-SAME: %[[UPDATE:arg[0-9]+]]: i1) -> i1
// CHECK: %[[WHOLE:.*]] = llvm.mlir.constant(255 : i64)
// CHECK: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_0
// CHECK: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// CHECK: %[[MASK_ADDR:.*]] = llvm.getelementptr %[[ACC]][64]
// CHECK-NEXT: %[[RAW_MASK:.*]] = llvm.load %[[MASK_ADDR]] {{.*}} : !llvm.ptr -> i64
// CHECK-NEXT: %[[WRITE_MASK:.*]] = llvm.and %[[RAW_MASK]], %[[WHOLE]] : i64
// CHECK-NEXT: %[[UNKNOWN_ADDR:.*]] = llvm.getelementptr %[[ACC]][32]
// CHECK-NEXT: %[[RAW_UNKNOWN:.*]] = llvm.load %[[UNKNOWN_ADDR]] {{.*}} : !llvm.ptr -> i64
// CHECK-NEXT: %[[STAGED_UNKNOWN:.*]] = llvm.select %[[UPDATE]], %[[RAW_UNKNOWN]], %[[ZERO]] : i1, i64
// CHECK: %[[COVERAGE:.*]] = llvm.select %[[UPDATE]], %[[WRITE_MASK]], %[[WHOLE]] : i1, i64
// CHECK-NEXT: %[[UNKNOWN:.*]] = llvm.or %[[STAGED_UNKNOWN]], %{{.*}} : i64
// CHECK-NEXT: %[[RELEVANT:.*]] = llvm.and %[[UNKNOWN]], %[[COVERAGE]] : i64
// CHECK-NEXT: %[[HAS_XZ:.*]] = llvm.icmp "ne" %[[RELEVANT]],
// CHECK-NEXT: llvm.cond_br %[[HAS_XZ]]

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic en = 0;
  logic [7:0] q = 'x;
  logic [15:0] idx = 0;
  always #5 clk = !clk;
  always @(posedge clk) begin
    if (en) q <= 8'ha5;
    else q[idx +: 2] <= 0;
  end
endmodule
