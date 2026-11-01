// CLAUSE: illegal internal source
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module cell_t(input wire a,output wire y);timeunit 1ns;timeprecision 1ps;wire internal=a;assign y=internal;specify (internal=>y)=2; endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic a=0;wire y;cell_t d(a,y);initial begin $display("PASS");$finish;end endmodule
