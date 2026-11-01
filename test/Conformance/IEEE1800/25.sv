// CLAUSE: Interfaces
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
interface A; bit[3:0] data=4'hc; modport view(input data); endinterface
interface B; bit[7:0] data=8'h31; modport view(input data); endinterface
module Reader(interface.view b,output int value); initial value=b.data; endmodule
module top; A a(); B b(); int x,y; Reader one(a,x),two(b,y); initial begin #1; if(x!=12 || y!=49) $fatal(1,"generic modport types"); $display("PASS"); $finish; end endmodule
