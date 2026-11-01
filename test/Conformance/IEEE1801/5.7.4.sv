// CLAUSE: Precedence resolution for isolation, level_shifter, and repeater strategies
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-elements' in set_isolation; the option is not implemented.
// Pins: two isolation strategies on one port: the port-specific one supplies the clamp, and the wide one still covers the rest (IEEE 1801-2018 5.7.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run a=1 b=1
// CHECK: iso a=0 b=1 inner=x

module leaf(output wire a,b);assign a=1;assign b=1;endmodule
module top;
import UPF::*;
logic iso=0;wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("run a=%b b=%b",a,b);
iso=1;void'(supply_off("/top/VDD"));#1;$display("iso a=%b b=%b inner=%b",a,b,dut.a);
$finish;
end
endmodule
