// CLAUSE: set_variation
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_variation"; the command is not implemented.
// Pins: set_variation affects no simulated value, and its operands are still checked (IEEE 1801-2018 6.54).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.54/base.upf -O3 --execution-tier=%tier %s -o %t.base.exe
// RUN: %t.base.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.54/design.upf -O3 --execution-tier=%tier %s -o %t.exe
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
