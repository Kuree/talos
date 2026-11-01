// CLAUSE: UPF is Tcl
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: UPF is ordinary Tcl: a proc, a return value and a loop compute which instances the domain holds (IEEE 1801-2018 5.1).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 1111
// CHECK: off x1x1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b,c,d;leaf u0(a),u1(b),u2(c),u3(d);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b%b",a,b,c,d);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b%b",a,b,c,d);
$finish;
end
endmodule
