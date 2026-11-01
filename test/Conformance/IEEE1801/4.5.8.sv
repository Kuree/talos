// CLAUSE: Supply correlation
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_correlated"; the command is not implemented.
// Pins: declaring supplies correlated constrains analysis only, so the simulation is unchanged, and an unknown supply is refused (IEEE 1801-2018 4.5.8).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.8/base.upf -O3 --execution-tier=%tier %s -o %t.base.exe
// RUN: %t.base.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on q=1
// CHECK: off q=x
// CHECK: on q=1
// CHECK: off q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VDDQ"));
#1;$display("on q=%b",q);
void'(supply_off("/top/VDD"));#1;$display("off q=%b",q);
$finish;
end
endmodule
