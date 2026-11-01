// CLAUSE: create_hdl2upf_vct
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_hdl2upf_vct"; the command is not implemented.
// Pins: a user table defines the conversion, here unlike any predefined one (IEEE 1801-2018 6.17).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/6.17/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: 0 FULL_ON
// CHECK: 1 OFF
// CHECK: x OFF
// CHECK: z OFF

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
