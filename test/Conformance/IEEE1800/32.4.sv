// CLAUSE: SDF IOPATH records replace module path delays
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module leaf(input wire a,output wire y);timeunit 1ns;timeprecision 1ns;assign y=a;specify(a=>y)=1;endspecify endmodule
module top;timeunit 1ns;timeprecision 1ns;logic a=0;wire y;leaf dut(a,y);initial begin
$sdf_annotate("delay.sdf",dut);#3;a=1;#1;if(y!==0)$fatal(1,"annotated delay too short");#3;if(y!==1)$fatal(1,"annotated delay missing");$display("PASS");$finish;end endmodule
