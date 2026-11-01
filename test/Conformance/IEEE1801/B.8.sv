// CLAUSE: SV_LOGIC2UPF_GNDZERO
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-vct' in connect_supply_net; the option is not implemented.
// Pins: the ground table inverts: logic 0 is FULL_ON and logic 1 is OFF (IEEE 1801-2018 B.8).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: 0 FULL_ON
// CHECK: 1 OFF
// CHECK: x UNDETERMINED
// CHECK: z UNDETERMINED

module drv(input logic d,output logic p);assign p=d;endmodule
module top;
import UPF::*;
logic d=0;wire p;drv dut(d,p);
task automatic row(logic v);upfSupplyTypeT s;d=v;#1;s=get_supply_value("/top/N");$display("%b %s",v,s.state.name());endtask
initial begin
row(1'b0);row(1'b1);row(1'bx);row(1'bz);
$finish;
end
endmodule
