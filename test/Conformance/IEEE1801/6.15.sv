// CLAUSE: connect_supply_set
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "connect_supply_set"; the command is not implemented.
// Pins: -connect ties each function of a set to the supply pins of that pg_type in the listed instance (IEEE 1801-2018 6.15).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.15/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: vddp FULL_ON 900000 vssp FULL_ON 0
// CHECK: vddp OFF

module macro((* UPF_pg_type="primary_power" *) input var UPF::supply_net_type vddp,(* UPF_pg_type="primary_ground" *) input var UPF::supply_net_type vssp,output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;macro dut(.q(q));
initial begin
void'(supply_on("/top/VDD",0.9));void'(supply_on("/top/VSS",0.0));
#1;$display("vddp %s %0d vssp %s %0d",dut.vddp.state.name(),dut.vddp.voltage,dut.vssp.state.name(),dut.vssp.voltage);
void'(supply_off("/top/VDD"));
#1;$display("vddp %s",dut.vddp.state.name());
$finish;
end
endmodule
