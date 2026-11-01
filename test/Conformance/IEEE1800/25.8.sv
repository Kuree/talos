// CLAUSE: Generic interface ports elaborate per actual parameterized interface instance.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
interface Bus #(parameter int W=3); bit[W-1:0] data; endinterface
module Reader(interface b,output int value); initial value=$bits(b.data)+b.W; endmodule
module top; Bus#(3) a(); Bus#(9) b(); int x,y; Reader one(a,x),two(b,y); initial begin #1; if(x!=6 || y!=18) $fatal(1,"generic specialization"); $display("PASS"); $finish; end endmodule
