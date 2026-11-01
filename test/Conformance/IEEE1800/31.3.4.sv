// CLAUSE: removal violation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire c,d,output reg n=0);timeunit 1ns;timeprecision 1ps;specify $removal(posedge d,posedge c,2,n); endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic c=0,d=0;wire n;cell_t dut(c,d,n);initial begin #9;c=1;#1;d=1;#3;if(n!==1)$fatal(1,"notifier=%b",n);$display("PASS");$finish;end endmodule
