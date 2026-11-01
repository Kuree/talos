// CLAUSE: Precedence resolution for supply connections
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "connect_supply_set"; the command is not implemented.
// Pins: a net connected directly to a pin takes precedence over a set connected to the same pin (IEEE 1801-2018 5.7.6).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/5.7.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: direct 700000 set 900000

module macro((* UPF_pg_type="primary_power" *) input var UPF::supply_net_type vddp,(* UPF_pg_type="primary_ground" *) input var UPF::supply_net_type vssp,output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire a,b;macro dut(.q(a)),other(.q(b));
initial begin
void'(supply_on("/top/VDD",0.9));void'(supply_on("/top/VSS",0.0));void'(supply_on("/top/DIRECT",0.7));
#1;$display("direct %0d set %0d",dut.vddp.voltage,other.vddp.voltage);
$finish;
end
endmodule
