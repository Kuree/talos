// CLAUSE: Phase 3 / recognize implemented power intent and process simulation control
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: supply object name conflicts with an HDL object; HDL supply-object reuse is not implemented.
// Pins: phase 3 recognizes an HDL supply object as the implementation of the UPF declaration of that name: they are one object, on both sides (IEEE 1801-2018 8.3.4).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/8.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/rail FULL_ON 900000
// CHECK: hdl FULL_ON 900000 q=1

module leaf(output wire q);assign q=1;endmodule
module top;
import UPF::*;
supply_net_type rail;
wire q;leaf dut(q);
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/rail",0.9));void'(supply_on("/top/VSS",0.0));
#1;show("/top/rail");$display("hdl %s %0d q=%b",rail.state.name(),rail.voltage,q);
$finish;
end
endmodule
