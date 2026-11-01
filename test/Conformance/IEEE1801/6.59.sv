// CLAUSE: use_interface_cell
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: "UPF requires a unique elaborated design top", because the uninstantiated cell model counts as a second top; use_interface_cell is also not implemented.
// Pins: the named cell implements the strategy: its model runs in the crossing, and the clamp comes from its function (IEEE 1801-2018 6.59).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.59/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: bound {{.*}}
// CHECK: run q=0
// CHECK: clamped q=1

module iso_or(input logic d,en,output wire y);assign y=d|en;initial $display("bound %m");endmodule
module leaf(output wire q);assign q=0;endmodule
module top;
import UPF::*;
logic iso=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("run q=%b",q);
iso=1;void'(supply_off("/top/VDD"));#1;$display("clamped q=%b",q);
$finish;
end
endmodule
