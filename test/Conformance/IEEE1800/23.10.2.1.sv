// CLAUSE: Ordered overrides bind value and type parameters in declaration order.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
module Leaf #(parameter int W=3, parameter type T=bit[W-1:0]); T value; initial value='1; endmodule
module top; Leaf#(5,byte) a(); initial begin #1; if(a.W!=5 || $bits(a.value)!=8 || a.value!==8'hff) $fatal(1,"ordered type override"); $display("PASS"); $finish; end endmodule
