// CLAUSE: sdf pulse limit
// XFAIL: *
// SDF PATHPULSE annotation is warned as unsupported and the pulse limit is not applied.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,output wire y);timeunit 1ns;timeprecision 1ps;assign y=a;specify (a=>y)=4; endspecify endmodule
module top;timeunit 1ns;timeprecision 1ps;logic a=0;wire y;cell_t d(a,y);initial $sdf_annotate("pulse.sdf",d);initial begin #6;a=1;#1;a=0;#3.5;if(y!==1)$fatal;#1;if(y!==0)$fatal;$display("PASS");$finish;end endmodule
