// CLAUSE: distributed path maximum
// XFAIL: *
// Combining a specify path and an explicitly delayed driver is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,output wire y);timeunit 1ns;timeprecision 1ps;buf #2 g(y,a);specify (a=>y)=4; endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic a=0;wire y;cell_t d(a,y);initial begin #6;a=1;#3;if(y!==0)$fatal;#2;if(y!==1)$fatal;$display("PASS");$finish;end endmodule
