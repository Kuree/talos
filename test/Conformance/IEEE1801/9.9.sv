// CLAUSE: Simulation of level-shifting
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_level_shifter"; the command is not implemented.
// Pins: a shifter passes its input while its supplies are on, and its output is corrupt when its output supply is off, whatever the source does (IEEE 1801-2018 9.9).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/9.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: pass 0 q=0
// CHECK: pass 1 q=1
// CHECK: output supply off q=x inner=1
// CHECK: restored q=1

module leaf(input logic d,output wire q);assign q=d;endmodule
module top;
import UPF::*;
logic d=0;wire q;leaf dut(d,q);
initial begin
void'(supply_on("/top/VDD",0.8));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VLS",1.0));
#1;$display("pass 0 q=%b",q);
d=1;#1;$display("pass 1 q=%b",q);
void'(supply_off("/top/VLS"));#1;$display("output supply off q=%b inner=%b",q,dut.q);
void'(supply_on("/top/VLS",1.0));#1;$display("restored q=%b",q);
$finish;
end
endmodule
