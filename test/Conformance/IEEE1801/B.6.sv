// CLAUSE: SV_LOGIC2UPF
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: unsupported UPF option '-vct' in connect_supply_net; the option is not implemented.
// Pins: each logic value of the driving port converts to its table state (IEEE 1801-2018 B.6).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: 0 OFF
// CHECK: 1 FULL_ON
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
