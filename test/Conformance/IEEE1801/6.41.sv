// CLAUSE: set_design_attributes
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_design_attributes"; the command is not implemented.
// Pins: attributes set on an instance change the domain extent: the macro below the attribute stays outside it (IEEE 1801-2018 6.41).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.41/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on macro=1 parent=1
// CHECK: off macro=1 parent=x

module leaf(output wire q);assign q=1;endmodule
module branch(output wire a,b);leaf mac(a);assign b=1;endmodule
module top;
import UPF::*;
wire a,b;branch dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("on macro=%b parent=%b",a,b);
void'(supply_off("/top/VDD"));#1;$display("off macro=%b parent=%b",a,b);
$finish;
end
endmodule
