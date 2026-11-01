// CLAUSE: defparam wins over an instance override and its RHS parameters come from the containing mo
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
module Leaf #(parameter int P=1); localparam int K=3; endmodule
module top; localparam int K=7; Leaf#(.P(5)) a(); defparam a.P=K;
initial begin if(a.P!=7) $fatal(1,"defparam precedence/scope"); $display("PASS"); $finish; end endmodule
