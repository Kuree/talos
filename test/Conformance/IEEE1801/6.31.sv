// CLAUSE: find_objects
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: find_objects with -pattern and -object_type: the matched instances form the domain (IEEE 1801-2018 6.31).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.31/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 111
// CHECK: off xx1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b,c;leaf u1(a),u2(b),v1(c);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b",a,b,c);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b",a,b,c);
$finish;
end
endmodule
