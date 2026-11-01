// CLAUSE: Simulation of repeaters
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_repeater"; the command is not implemented.
// Pins: a repeater passes its input while powered and corrupts only its output when its supply is off; its source stays known (IEEE 1801-2018 9.10).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.10/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: pass 0 q=0
// CHECK: pass 1 q=1
// CHECK: off q=x inner=1
// CHECK: back q=1

module leaf(input logic d,output wire q);assign q=d;endmodule
module top;
import UPF::*;
logic d=0;wire q;leaf dut(d,q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRP"));
#1;$display("pass 0 q=%b",q);
d=1;#1;$display("pass 1 q=%b",q);
void'(supply_off("/top/VRP"));#1;$display("off q=%b inner=%b",q,dut.q);
void'(supply_on("/top/VRP"));#1;$display("back q=%b",q);
$finish;
end
endmodule
