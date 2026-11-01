// CLAUSE: Supply nets defined in HDL
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unknown supply net, port, or function: rail; HDL supply nets are not visible to UPF.
// Pins: a supply net declared in HDL is the object UPF connects to: supply_on through its name reaches the domain and the HDL variable (IEEE 1801-2018 6.24.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.24.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: on FULL_ON 900000 q=1
// CHECK: off OFF q=x

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
supply_net_type rail,gnd;
wire q;leaf dut(q);
initial begin
void'(supply_on("/top/rail",0.9));void'(supply_on("/top/gnd",0.0));
#1;$display("on %s %0d q=%b",rail.state.name(),rail.voltage,q);
void'(supply_off("/top/rail"));
#1;$display("off %s q=%b",rail.state.name(),q);
$finish;
end
endmodule
