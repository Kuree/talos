// CLAUSE: define_level_shifter_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_level_shifter_cell"; the command is not implemented.
// Pins: a defined level-shifter cell's output follows its output power pin, not its domain: known with that pin on, corrupt with it off (IEEE 1801-2018 7.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on y=1
// CHECK: domain off y=1
// CHECK: output pin off y=x

module shifter(input logic a,output wire y);assign y=a;endmodule
module cluster(input logic a,output wire y);shifter u(a,y);endmodule
module top;
import UPF::*;
wire y;cluster dut(1'b1,y);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VOUT"));void'(supply_on("/top/VIN"));
#1;$display("on y=%b",y);
void'(supply_off("/top/VDD"));#1;$display("domain off y=%b",y);
void'(supply_off("/top/VOUT"));#1;$display("output pin off y=%b",y);
$finish;
end
endmodule
