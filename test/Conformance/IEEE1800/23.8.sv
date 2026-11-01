// CLAUSE: An unqualified function call searches enclosing module hierarchy when no lexical/CU functi
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
module Leaf; function automatic int sample(); return get_id(); endfunction endmodule
module Middle #(parameter int ID=0); function automatic int get_id(); return ID; endfunction Leaf u(); endmodule
module top; Middle#(7) a(); Middle#(11) b(); initial begin if(a.u.sample()!=7 || b.u.sample()!=11) $fatal(1,"upward function binding"); $display("PASS"); $finish; end endmodule
