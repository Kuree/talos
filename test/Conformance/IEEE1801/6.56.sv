// CLAUSE: sim_corruption_control
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "sim_corruption_control"; the command is not implemented.
// Pins: a signal named in the control is not corrupted with its domain, while its sibling is (IEEE 1801-2018 6.56).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.56/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on keep=1 drop=1
// CHECK: off keep=1 drop=x

module leaf(output wire keep,drop);assign keep=1;assign drop=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on keep=%b drop=%b",dut.keep,dut.drop);
void'(supply_off("/top/VDD"));#1;$display("off keep=%b drop=%b",dut.keep,dut.drop);
$finish;
end
endmodule
