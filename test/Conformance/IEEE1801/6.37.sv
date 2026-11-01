// CLAUSE: map_retention_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; map_retention_cell is also not implemented.
// Pins: the retention strategy maps to a named model, which is instantiated, and the retained value still comes back (IEEE 1801-2018 6.37).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.37/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: mapped {{.*}}
// CHECK: off q=x
// CHECK: back q=1

module ret_model;initial $display("mapped %m");endmodule
module regcell(input logic clk,d,output logic q=0);always @(posedge clk)q<=d;endmodule
module top;
import UPF::*;
logic clk=0,rtc=0;wire q;regcell dut(clk,1'b1,q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;rtc=1;void'(supply_off("/top/VDD"));#1;$display("off q=%b",q);
void'(supply_on("/top/VDD"));#1;$display("back q=%b",q);
$finish;
end
endmodule
