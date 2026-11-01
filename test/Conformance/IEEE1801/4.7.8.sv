// CLAUSE: Power state control
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_power_state'; the HDL power-state control function is not implemented.
// Pins: HDL control selects a deferred state, and the domain follows its simstate (IEEE 1801-2018 4.7.8, 11.2.3.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: default q=1
// CHECK: set RET=1
// CHECK: RET q=x
// CHECK: set ON=1
// CHECK: ON q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("default q=%b",q);
$display("set RET=%b",set_power_state("/top/CORE","RET"));#1;$display("RET q=%b",q);
$display("set ON=%b",set_power_state("/top/CORE","ON"));#1;$display("ON q=%b",q);
$finish;
end
endmodule
