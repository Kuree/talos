// CLAUSE: Logic expression
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported power-state option: -logic_expr; the option is not implemented.
// Pins: -logic_expr qualifies a state from HDL logic: the state and its simstate change with en while the supply stays on (IEEE 1801-2018 6.5.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.5.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: en=1 q=1
// CHECK: en=0 q=x
// CHECK: en=1 q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic en=1;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("en=1 q=%b",q);
en=0;#1;$display("en=0 q=%b",q);
en=1;#1;$display("en=1 q=%b",q);
$finish;
end
endmodule
