// CLAUSE: pulse on detect
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,output wire y);timeunit 1ns;timeprecision 1ps;assign y=a;specify specparam PATHPULSE$=(2,4);pulsestyle_ondetect y;(a=>y)=4; endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic a=0;wire y;cell_t d(a,y);initial begin #10;a=1;#3;a=0;#0.5;if(y!==1'bx)$fatal;#4;if(y!==0)$fatal;$display("PASS");$finish;end endmodule
