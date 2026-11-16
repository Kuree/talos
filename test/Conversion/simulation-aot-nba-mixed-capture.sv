// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 clocked-kernels=off' | FileCheck %s --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.6(b), 4.9.4, 10.4.2: a runtime capture may consume a
// generated shadow and then be followed by another generated capture.
// Retain the static capture ABI and guard the direct barrier before it reads
// or consumes the dirty index. Its failed-guard edge reaches the canonical
// static commit; it must not unconditionally consume a runtime-owned root.
// This checks the compiler's guard protocol, not its runtime implementation.
//
// CHECK-LABEL: llvm.func @{{unit_[0-9]+}}.__talos_group_body(
// CHECK: llvm.call @talos_rt_v1_scheduler_static_nba(
// CHECK-SAME: schedule.eval.pending_runtime_root = 0 : i32
// CHECK: llvm.getelementptr %{{.*}}[64]
// CHECK: llvm.store
//
// CHECK-LABEL: llvm.func @__talos_aot_static_nba_commit_v1(
// CHECK: %[[DIRTY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// CHECK-NOT: llvm.load %[[DIRTY]]
// CHECK: %[[GUARD:.*]] = llvm.call @talos_rt_v1_static_nba_direct_commit_guard(
// CHECK-NEXT: %[[DIRECT:.*]] = llvm.icmp "ne" %[[GUARD]],
// CHECK-NEXT: llvm.cond_br %[[DIRECT]], ^[[GENERATED:bb[0-9]+]], ^[[CANONICAL:bb[0-9]+]]
// CHECK: ^[[GENERATED]]:
// CHECK: llvm.load %[[DIRTY]]
// CHECK: ^[[CANONICAL]]:
// CHECK: llvm.call @talos_rt_v1_static_nba_commit_roots(
// CHECK-NEXT: llvm.return

`timescale 1ns/1ps
module top;
  bit clk = 0;
  logic [2:0] en = 0;
  logic signed [63:0] idx = 0, captured_idx = 0;
  logic [95:0] d = 0, scratch = 0;
  logic [30:0] q = 31'b0001000100000111001000100011000;
  logic [30:0] r = 31'b0000010100010010101111010001001;
  always #5 clk = !clk;
  task automatic put(input logic signed [63:0] at,
                     input logic [95:0] value);
    q[at +: 7] <= value[6:0];
  endtask
  always @(posedge clk) begin
    if (en[0]) put(idx, d);
    if (en[0]) q[captured_idx] <= scratch[0:0];
    if (en[1]) q[captured_idx +: 13] <= scratch[12:0];
  end
  always @(posedge clk) r <= q;
  initial begin
    #3; idx = 30; en = 3'b111; d = 96'bz;
  end
endmodule
