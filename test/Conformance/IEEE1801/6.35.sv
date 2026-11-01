// CLAUSE: map_power_switch
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; map_power_switch is also not implemented.
// Pins: the abstract switch maps to a named cell, whose model is instantiated, with the switch behaviour unchanged (IEEE 1801-2018 6.35).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.35/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: mapped {{.*}}
// CHECK: open q=x
// CHECK: closed q=1

module sw_model(input logic ctl);initial $display("mapped %m");endmodule
module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("open q=%b",q);
en=1;#1;$display("closed q=%b",q);
$finish;
end
endmodule
