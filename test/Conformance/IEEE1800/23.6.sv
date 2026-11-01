// CLAUSE: A constant expression can select a named generate instance array.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
module top; localparam int INDEX=1; for(genvar i=0;i<2;i++) begin:g localparam int VALUE=i; end
initial begin if(g[INDEX].VALUE!=1) $fatal(1,"constant hierarchy index"); $display("PASS"); $finish; end endmodule
