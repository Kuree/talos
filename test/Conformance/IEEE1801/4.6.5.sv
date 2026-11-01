// CLAUSE: Power-management requirements
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_repeater"; the command is not implemented.
// Pins: a repeater requirement inserts a power-aware buffer: every selected output depends on the repeater supply, not the domain supply (IEEE 1801-2018 4.6.5).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.6.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on a=1 b=1 inner=1
// CHECK: off a=x b=x inner=1

module leaf(output wire a,b);assign a=1;assign b=1;endmodule
module top;
import UPF::*;
wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/VRP"));
#1;$display("on a=%b b=%b inner=%b",a,b,dut.a);
void'(supply_off("/top/VRP"));#1;$display("off a=%b b=%b inner=%b",a,b,dut.a);
$finish;
end
endmodule
