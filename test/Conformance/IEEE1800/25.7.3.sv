// CLAUSE: An interface extern/export function can be implemented in a connected module and called th
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
interface Bus; extern function int calc(input int x); modport owner(export calc); modport client(import function int calc(input int x)); endinterface
module Implement(Bus.owner b); function int b.calc(input int x); return x+2; endfunction endmodule
module Reader(Bus.client b,output int value); initial value=b.calc(5); endmodule
module top; Bus bus(); int value; Implement impl(bus); Reader reader(bus,value); initial begin #1; if(value!=7) $fatal(1,"exported function"); $display("PASS"); $finish; end endmodule
