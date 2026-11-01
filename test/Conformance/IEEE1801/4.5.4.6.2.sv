// CLAUSE: Explicit and automatic connections
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unknown supply port: dut/m2/vddp; HDL supply pins cannot be connected, explicitly or automatically.
// Pins: an explicit connection names its pin, and an unnamed pin of the same pg_type connects automatically to its domain's primary set (IEEE 1801-2018 4.5.4.6.2).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.4.6.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: automatic 900000 explicit 700000

module macro((* UPF_pg_type="primary_power" *) input var UPF::supply_net_type vddp,(* UPF_pg_type="primary_ground" *) input var UPF::supply_net_type vssp,output wire q);assign q=1;endmodule
module cluster(output wire a,b);macro m1(.q(a)),m2(.q(b));endmodule
module top;
import UPF::*;
wire a,b;cluster dut(a,b);
initial begin
void'(supply_on("/top/VDD",0.9));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/OTHER",0.7));
#1;$display("automatic %0d explicit %0d",dut.m1.vddp.voltage,dut.m2.vddp.voltage);
$finish;
end
endmodule
