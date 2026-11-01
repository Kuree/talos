// CLAUSE: vector lsb event
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire[1:0]c,input wire d,output reg n=0);timeunit 1ns;timeprecision 1ps;specify $setup(posedge d,posedge c,2,n); endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic[1:0]c=0;logic d=0;wire n;cell_t dut(c,d,n);initial begin #9;d=1;#1;c=2;#1;if(n!==0)$fatal;#2;d=0;#1;d=1;#1;c=3;#1;if(n!==1)$fatal(1,"notifier=%b",n);$display("PASS");$finish;end endmodule
