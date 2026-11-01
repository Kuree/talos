// CLAUSE: Power intent commands
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: chapter sample: the supply, domain, switch and power-state commands together drive one output (IEEE 1801-2018 6.5, 6.20, 6.22, 6.24, 6.26).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: switch open q=x
// CHECK: closed q=1
// CHECK: low q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("switch open q=%b",q);
en=1;#1;$display("closed q=%b",q);
void'(supply_on("/top/VDD",0.8));#1;$display("low q=%b",q);
$finish;
end
endmodule
