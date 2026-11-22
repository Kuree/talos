// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3' | FileCheck %s

// IEEE 1800-2023 4.6(b), 9.4.2.3: iff samples en when clk changes,
// before the following source-ordered NBA changes en. A later en change
// cannot retroactively admit or cancel the edge. Both roots must retain
// ordered publication; independently merging en before queued clk is wrong.
// The runtime queues the four NBAs in source order: clk, en, clk, en (the
// destination handle is the fifth operand). A handle names a static state
// object (tag bit 62) by its ID in bits 32-61: clk is object 1 and en object 2,
// both at offset 0.
// CHECK-LABEL: llvm.func @unit_4.__talos_coro_ramp(
// CHECK-DAG: [[CLK:%[0-9]+]] = llvm.mlir.constant(4611686022722355200 : i64) : i64
// CHECK-DAG: [[EN:%[0-9]+]] = llvm.mlir.constant(4611686027017322496 : i64) : i64
// CHECK: llvm.call @talos_rt_v1_scheduler_nba({{[^,]+}}, {{[^,]+}}, {{[^,]+}}, {{[^,]+}}, [[CLK]],
// CHECK: llvm.call @talos_rt_v1_scheduler_nba({{[^,]+}}, {{[^,]+}}, {{[^,]+}}, {{[^,]+}}, [[EN]],
// CHECK: llvm.call @talos_rt_v1_scheduler_nba({{[^,]+}}, {{[^,]+}}, {{[^,]+}}, {{[^,]+}}, [[CLK]],
// CHECK: llvm.call @talos_rt_v1_scheduler_nba({{[^,]+}}, {{[^,]+}}, {{[^,]+}}, {{[^,]+}}, [[EN]],
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
