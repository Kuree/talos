// CLAUSE: Precedence resolution for power domains
// REQUIRES: upf
// XFAIL: *
// nested switchable domains are not implemented: top.Q and top.P
// Pins: a nested instance in its own domain is outside its parent's: the parent powering off corrupts the parent only (IEEE 1801-2018 5.7.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on child=1 parent=1
// CHECK: off child=1 parent=x

module leaf(output wire q);assign q=1;endmodule
module branch(output wire a,b);leaf child(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b;branch dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VQ"));void'(supply_on("/top/VQS",0.0));
#1;$display("on child=%b parent=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off child=%b parent=%b",a,b);
$finish;
end
endmodule
