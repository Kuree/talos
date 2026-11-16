// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s

// IEEE 1800-2023 4.6(b), 9.4.2.3: iff samples en when clk changes,
// before the following source-ordered NBA changes en. A later en change
// cannot retroactively admit or cancel the edge. Both roots must retain
// ordered publication; independently merging en before queued clk is wrong.
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-SAME: schedule.eval.pending_runtime_root = 0 : i32
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-SAME: schedule.eval.pending_runtime_root = 1 : i32
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-SAME: schedule.eval.pending_runtime_root = 0 : i32
// CHECK: llvm.call @talos_rt_v1_scheduler_nba(
// CHECK-SAME: schedule.eval.pending_runtime_root = 1 : i32
// CHECK-NOT: llvm.call @talos_rt_v1_scheduler_nba(

`timescale 1ns/1ps
module top;
  logic clk=0,en=0;
  integer fired=0;
  always @(posedge clk iff en) fired=fired+1;
  initial begin
    #1; clk=0; en=1;
    #1; clk<=1; en<=0;
    #1; $display("%0d %b",fired,en);
    #1; clk=0; en=0;
    #1; clk<=1; en<=1;
    #1; $display("%0d %b",fired,en);
    $finish;
  end
endmodule
