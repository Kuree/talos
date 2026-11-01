// CLAUSE: SDF SETUP annotation changes the notifier
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module delay_cell(input wire d,c,output logic n=0);
timeunit 1ns;timeprecision 1ns;specify $setup(posedge d,posedge c,1,n);endspecify
endmodule
module top;timeunit 1ns;timeprecision 1ns;logic d=0,c=0;wire n;delay_cell dut(d,c,n);
initial begin $sdf_annotate("delay.sdf",dut);#5;d=1;#2;c=1;#2;
if(n!==1)$fatal(1,"annotation notifier");$display("PASS");$finish;end
endmodule
