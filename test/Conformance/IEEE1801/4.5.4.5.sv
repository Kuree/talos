// CLAUSE: Supply net/supply set connections
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "connect_supply_set"; the command is not implemented.
// Pins: a set reaches a pin through its function's net: pin, function and net all read one value (IEEE 1801-2018 4.5.4.5, 6.15).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/4.5.4.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: /top/VDD FULL_ON 700000
// CHECK: pin FULL_ON 700000

module macro((* UPF_pg_type="primary_power" *) input var UPF::supply_net_type vddp,(* UPF_pg_type="primary_ground" *) input var UPF::supply_net_type vssp,output wire q);assign q=1;endmodule
module top;
import UPF::*;
wire q;macro dut(.q(q));
function automatic void show(string name);
upfSupplyTypeT s=get_supply_value(name);
$display("%s %s %0d",name,s.state.name(),s.voltage);
endfunction
initial begin
void'(supply_on("/top/CORE.power",0.7));
#1;show("/top/VDD");$display("pin %s %0d",dut.vddp.state.name(),dut.vddp.voltage);
$finish;
end
endmodule
