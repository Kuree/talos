// CLAUSE: Isolation and level-shifting
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_level_shifter"; the command is not implemented.
// Pins: on one crossing the clamp holds a powered-down source, and the shifter still needs its own output supply (IEEE 1801-2018 4.4.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.4.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: powered q=1
// CHECK: clamped q=0
// CHECK: no shifter q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic iso=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VLS"));
#1;$display("powered q=%b",q);
iso=1;void'(supply_off("/top/VDD"));#1;$display("clamped q=%b",q);
void'(supply_off("/top/VLS"));#1;$display("no shifter q=%b",q);
$finish;
end
endmodule
