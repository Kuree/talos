// CLAUSE: effective_element_list semantics
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-exclude_elements' in create_power_domain; the option is not implemented.
// Pins: the effective list is the elements minus the exclusions: an excluded child is not in the domain (IEEE 1801-2018 5.9).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.9/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on child=1 parent=1 other=1
// CHECK: off child=1 parent=x other=1

module leaf(output wire q);assign q=1;endmodule
module branch(output wire a,b);leaf child(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b,c;branch dut(a,b);leaf other(c);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on child=%b parent=%b other=%b",a,b,c);
void'(supply_off("/top/VDD"));#1;$display("off child=%b parent=%b other=%b",a,b,c);
$finish;
end
endmodule
