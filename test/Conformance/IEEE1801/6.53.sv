// CLAUSE: set_simstate_behavior
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_simstate_behavior"; the command is not implemented.
// Pins: DISABLE turns off corruption for the named model, so its instance stays known while its supply is off (IEEE 1801-2018 6.53).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.53/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 11
// CHECK: off 1x

module leaf(output wire q);assign q=1;endmodule
module other_leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a);other_leaf sib(b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off %b%b",a,b);
$finish;
end
endmodule
