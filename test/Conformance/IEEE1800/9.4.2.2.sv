// CLAUSE: wildcard assert action included
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

int src=3,out=0;
always @* assert(1) out=src;
initial begin #1; src=7; #1; if(out!=7) $fatal; $display("PASS"); $finish; end

endmodule
