// CLAUSE: Attributes of objects
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "set_port_attributes"; the command is not implemented.
// Pins: a port attribute means the same from HDL and from UPF: both clamp values reach the isolation strategy, which names none itself (IEEE 1801-2018 5.6, 6.48).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: run a=0 b=0
// CHECK: clamped a=1 b=1

module leaf((* UPF_clamp_value="1" *) output wire a,output wire b);assign a=0;assign b=0;endmodule
module top;
import UPF::*;
logic iso=0;wire a,b;leaf dut(a,b);
initial begin
void'(supply_on("/top/VDD"));void'(supply_on("/top/VSS",0.0));
#1;$display("run a=%b b=%b",a,b);
iso=1;void'(supply_off("/top/VDD"));#1;$display("clamped a=%b b=%b",a,b);
$finish;
end
endmodule
