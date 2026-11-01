// CLAUSE: set_equivalent
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_port_attributes"; the command is not implemented.
// Pins: supplies declared equivalent count as one for -diff_supply_only, so the crossing from A to B gets no clamp (IEEE 1801-2018 6.44).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.44/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run q=1
// CHECK: iso q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
logic iso=0;wire q;leaf dut(q);
initial begin
void'(supply_on("/top/VA"));void'(supply_on("/top/VB"));void'(supply_on("/top/VSS",0.0));
#1;$display("run q=%b",q);
iso=1;#1;$display("iso q=%b",q);
$finish;
end
endmodule
