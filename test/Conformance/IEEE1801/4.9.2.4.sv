// CLAUSE: Macro cells
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "define_power_model"; the command is not implemented.
// Pins: a macro is a design element with its own power model: the model's domain governs it, not the surrounding one (IEEE 1801-2018 4.9.2.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.9.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on macro=x parent=1
// CHECK: off macro=x parent=x

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
