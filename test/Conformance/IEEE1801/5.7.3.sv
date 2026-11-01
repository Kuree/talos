// CLAUSE: Precedence resolution for retention strategies
// SINCE: 0.1.0
// REQUIRES: upf
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf(input logic clk,output logic q=0);always @(posedge clk)q<=1;endmodule
module top;import UPF::*;logic clk=0,en=1,rtc=0,never=0;wire q;leaf dut(clk,q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;rtc=1;en=0;#1;en=1;#1;
if(q!==1)$fatal(1,"retention precedence");
$display("PASS");$finish;
end endmodule
