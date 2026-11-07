// CLAUSE: create_composite_domain
// SINCE: 0.2.0
// REQUIRES: upf
// Pins: an unbound child receives the composite primary; a supplied interchangeable child keeps its distinct rail; an outside domain is unaffected (IEEE 1801-2018 6.16).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.16/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 111
// CHECK: off xx1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b,c;leaf u0(a),u1(b),u2(c);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VDD2"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b",a,b,c);
void'(supply_off("/top/VDD"));void'(supply_off("/top/VDD2"));#1;$display("off %b%b%b",a,b,c);
$finish;
end
endmodule
