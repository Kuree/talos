// CLAUSE: Value conversion tables
// REQUIRES: upf
// XFAIL: *
// UPF execution failed: invalid command name "create_hdl2upf_vct"; the command is not implemented.
// Pins: chapter sample: an HDL signal drives a supply through a value conversion table (IEEE 1801-2018 Annex B).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/B/design.upf -O3 --execution-tier=%tier %s -o %t.exe
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
