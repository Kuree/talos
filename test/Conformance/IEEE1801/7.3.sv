// CLAUSE: define_diode_clamp
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_diode_clamp"; the command is not implemented.
// Pins: a diode clamp is a protection structure with no logic function: the data pin still simulates normally, and naming a pin the cell lacks is refused (IEEE 1801-2018 7.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.3/base.upf -O3 --execution-tier=%tier %s -o %t.base.exe
// RUN: %t.base.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on y=1
// CHECK: on y=0
// CHECK: off y=x
// CHECK: on y=1
// CHECK: on y=0
// CHECK: off y=x

module clamp(input logic d,output wire y);assign y=d;endmodule
module top;
import UPF::*;
logic d=1;wire y;clamp dut(d,y);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on y=%b",y);
d=0;#1;$display("on y=%b",y);
void'(supply_off("/top/VDD"));#1;$display("off y=%b",y);
$finish;
end
endmodule
