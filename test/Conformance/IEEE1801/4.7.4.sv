// CLAUSE: Predefined power states
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: predefined ON needs every required function FULL_ON; otherwise predefined OFF corrupts (IEEE 1801-2018 4.7.4, 9.3.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: power only q=x
// CHECK: both q=1
// CHECK: ground off q=x
// CHECK: restored q=1
// CHECK: power off q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));#1;$display("power only q=%b",q);
void'(supply_on("/top/VSS",0.0));#1;$display("both q=%b",q);
void'(supply_off("/top/VSS"));#1;$display("ground off q=%b",q);
void'(supply_on("/top/VSS",0.0));#1;$display("restored q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("power off q=%b",q);
$finish;
end
endmodule
