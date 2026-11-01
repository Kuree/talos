// CLAUSE: set_level_shifter
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_level_shifter"; the command is not implemented.
// Pins: -rule filters by voltage direction: a low_to_high strategy shifts the 0.8 V to 1.0 V crossing and depends on its supply; a high_to_low strategy would not (IEEE 1801-2018 6.46).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.46/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: ls on q=1 inner=1
// CHECK: ls off q=x inner=1

module leaf(output wire up);assign up=1;endmodule
module top;
import UPF::*;
wire up;leaf dut(up);
initial begin
void'(supply_on("/top/VDD",0.8));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VLS",1.0));
#1;$display("ls on q=%b inner=%b",up,dut.up);
void'(supply_off("/top/VLS"));#1;$display("ls off q=%b inner=%b",up,dut.up);
$finish;
end
endmodule
