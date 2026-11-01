// CLAUSE: Objects with power states
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'set_power_state'; the HDL power-state control function is not implemented.
// Pins: supply sets and domains both carry power states: a domain state named from the set's state selects the domain behaviour (IEEE 1801-2018 4.7.5, 6.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.7.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: default q=1
// CHECK: DOWN q=x
// CHECK: RUN q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("default q=%b",q);
void'(set_power_state("/top/PD","DOWN"));#1;$display("DOWN q=%b",q);
void'(set_power_state("/top/PD","RUN"));#1;$display("RUN q=%b",q);
$finish;
end
endmodule
