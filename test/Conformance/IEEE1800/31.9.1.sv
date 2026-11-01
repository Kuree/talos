// CLAUSE: negative setup delayed reference
// XFAIL: *
// Explicit delayed_reference/delayed_data of a negative check carry a nonzero solved delay; the declared net has no delayed driver yet (only the zero-delay copy of 31.9.4 is executable).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire c,d,output reg q=0);timeunit 1ns;timeprecision 1ps;wire dc,dd;reg n=0;
always @(posedge dc)q<=dd;
specify $setuphold(posedge c,d,-2,5,n,,,dc,dd);endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic c=0,d=0;wire q;cell_t dut(c,d,q);
initial begin #10;c=1;#1;d=1;#2;if(q!==1)$fatal;$display("PASS");$finish;end endmodule
