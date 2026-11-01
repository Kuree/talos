// CLAUSE: set_port_attributes
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_port_attributes"; the command is not implemented.
// Pins: -receiver_supply makes a port same-supply, so -diff_supply_only leaves it unclamped while its unattributed sibling is clamped (IEEE 1801-2018 6.48).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.48/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run a=1 b=1
// CHECK: iso a=1 b=0

module leaf(output wire a,b);assign a=1;assign b=1;endmodule
module top;
import UPF::*;
logic iso=0;wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VAON"));
#1;$display("run a=%b b=%b",a,b);
iso=1;#1;$display("iso a=%b b=%b",a,b);
$finish;
end
endmodule
