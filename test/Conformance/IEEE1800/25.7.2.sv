// CLAUSE: Imported prototype defaults take precedence over defaults in the interface function declar
// XFAIL: *
// A call through a modport uses the declaration default instead of the prototype default.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
interface Bus; function int bump(input int x=4); return x+1; endfunction modport client(import function int bump(input int x=7)); endinterface
module Reader(Bus.client b,output int value); initial value=b.bump(); endmodule
module top; Bus bus(); int value; Reader r(bus,value); initial begin #1; if(value!=8 || bus.bump()!=5) $fatal(1,"modport default"); $display("PASS"); $finish; end endmodule
