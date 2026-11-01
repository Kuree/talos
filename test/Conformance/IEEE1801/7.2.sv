// CLAUSE: define_always_on_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_always_on_cell"; the command is not implemented.
// Pins: an always-on cell inside a switched domain keeps evaluating from its always-on pin while the domain is off (IEEE 1801-2018 7.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on y=1 z=1
// CHECK: off y=1 z=x
// CHECK: off a=0 y=0 z=x

module aon(input logic a,output wire y);assign y=a;endmodule
module cluster(input logic a,output wire y,z);aon u(a,y);assign z=a;endmodule
module top;
import UPF::*;
logic a=1;wire y,z;cluster dut(a,y,z);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VAON"));
#1;$display("on y=%b z=%b",y,z);
void'(supply_off("/top/VDD"));#1;$display("off y=%b z=%b",y,z);
a=0;#1;$display("off a=0 y=%b z=%b",y,z);
$finish;
end
endmodule
