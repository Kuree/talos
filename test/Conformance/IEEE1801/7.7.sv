// CLAUSE: define_retention_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_retention_cell"; the command is not implemented.
// Pins: a defined retention cell keeps its state across primary loss through its retention power pin; plain logic does not (IEEE 1801-2018 7.7).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.7/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run q=1 z=1
// CHECK: off z=x
// CHECK: back q=1 z=1

module retflop(input logic clk,d,save,output logic q=0);always @(posedge clk)if(!save)q<=d;endmodule
module cluster(input logic clk,d,save,output wire q,z);retflop u(clk,d,save,q);assign z=1;endmodule
module top;
import UPF::*;
logic clk=0,d=1,save=0;wire q,z;cluster dut(clk,d,save,q,z);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRET"));
#1;clk=1;#1;clk=0;#1;$display("run q=%b z=%b",q,z);
save=1;#1;void'(supply_off("/top/VDD"));#1;$display("off z=%b",z);
void'(supply_on("/top/VDD"));#1;save=0;#1;$display("back q=%b z=%b",q,z);
$finish;
end
endmodule
