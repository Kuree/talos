// CLAUSE: General treatment of precedence
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: no rule ordering two strategies with the same selection is an error, reported at the second; a selection that does order them simulates (IEEE 1801-2018 5.7.9).
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.9/illegal.upf -O3 --execution-tier=%tier %s -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: restored q=1
// DIAG: ambiguous retention strategies for top.dut.q

module leaf(input logic clk,output logic q=0);always @(posedge clk)q<=1;endmodule
module top;
import UPF::*;
logic clk=0,keep=0,never=0;wire q;leaf dut(clk,q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;keep=1;void'(supply_off("/top/VDD"));#1;void'(supply_on("/top/VDD"));#1;
$display("restored q=%b",q);
$finish;
end
endmodule
