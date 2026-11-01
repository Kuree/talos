// CLAUSE: create_composite_domain
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_composite_domain"; the command is not implemented.
// Pins: the composite's primary supply reaches each subdomain, and it does not reach a domain outside it (IEEE 1801-2018 6.16).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.16/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on 111
// CHECK: off xx1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b,c;leaf u0(a),u1(b),u2(c);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on %b%b%b",a,b,c);
void'(supply_off("/top/VDD"));#1;$display("off %b%b%b",a,b,c);
$finish;
end
endmodule
