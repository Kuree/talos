// CLAUSE: Pulse limit annotation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module delay_cell(input wire a,output wire y);timeunit 1ns;timeprecision 1ns;assign y=a;specify(a=>y)=0;endspecify endmodule
module top;timeunit 1ns;timeprecision 1ns;logic a=0;wire y;int rises=0;always @(posedge y)if($time>5)rises++;delay_cell dut(a,y);
initial begin $sdf_annotate("delay.sdf",dut);#10;a=1;#1;a=0;#8;if(y!==0 || rises!=0)$fatal(1,"pulse");
$display("PASS");$finish;end endmodule
