// CLAUSE: Design data can be passed into a package function through ordinary arguments.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
package P; function automatic int read(input int value); return value; endfunction endpackage
module top; int value=7; initial begin if(P::read(value)!=7) $fatal(1,"package argument"); $display("PASS"); $finish; end endmodule
