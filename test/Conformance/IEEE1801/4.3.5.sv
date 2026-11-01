// CLAUSE: Design hierarchy
// SINCE: 0.1.0
// REQUIRES: upf
// Pins: transitive search reaches a nested instance, whose result alone forms the domain; its parent and sibling stay powered (IEEE 1801-2018 4.3.5, 6.31).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.3.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on child=1 parent=1 sibling=1
// CHECK: off child=x parent=1 sibling=1

module leaf(output wire q);assign q=1;endmodule
module branch(output wire a,b);leaf child(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b,c;branch dut(a,b);leaf other(c);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on child=%b parent=%b sibling=%b",a,b,c);
void'(supply_off("/top/VDD"));#1;$display("off child=%b parent=%b sibling=%b",a,b,c);
$finish;
end
endmodule
