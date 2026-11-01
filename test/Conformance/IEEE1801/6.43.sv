// CLAUSE: set_domain_supply_net (legacy)
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: legacy primary nets power the domain: power and ground are each required, and the command returns 1 (IEEE 1801-2018 6.43).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.43/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on q=1
// CHECK: ground off q=x
// CHECK: on q=1
// CHECK: power off q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on q=%b",q);
void'(supply_off("/top/VSS"));#1;$display("ground off q=%b",q);
void'(supply_on("/top/VSS",0.0));#1;$display("on q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("power off q=%b",q);
$finish;
end
endmodule
