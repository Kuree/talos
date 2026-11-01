// CLAUSE: Power-management concepts
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: chapter sample: a switched domain with a parent-located clamp and a retained register, through one power cycle (IEEE 1801-2018 4.4, 4.5, 4.7, 9.5.3, 9.7.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run inner=1 outer=1
// CHECK: off inner=x outer=0
// CHECK: back inner=1 outer=1

module regcell(input logic clk,d,output logic q=0);always @(posedge clk)q<=d;endmodule
module top;
import UPF::*;
logic clk=0,en=1,rtc=0,iso=0;wire q;regcell dut(clk,1'b1,q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;$display("run inner=%b outer=%b",dut.q,q);
iso=1;rtc=1;en=0;#1;$display("off inner=%b outer=%b",dut.q,q);
en=1;#1;rtc=0;iso=0;#1;$display("back inner=%b outer=%b",dut.q,q);
$finish;
end
endmodule
