// CLAUSE: Generic interconnect: an interconnect net reports vpiInterconnect, takes its typespec from what it connects, and an interconnect array iterates vpiElement
// XFAIL: *
// interconnect net reports resolved=0 where the probe expects 1; the required value is unverified against 37
// RUN: %clang -c -fPIC %S/Inputs/37.24/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: net type=vpiInterconnectNet nettype=1 resolved=1 typespec=vpiLogicTypespec size=4
// CHECK: array type=vpiInterconnectArray packed=0 size=2 left=0 right=1 typespec=null
// CHECK: elements=2 first=vpiInterconnectNet
// CHECK: through sink i=9 j=6 k=3

module drv #(parameter logic [3:0] V = 0) (output wire logic [3:0] o);
assign o = V;
endmodule
module snk(input wire logic [3:0] i);
endmodule
module top;
interconnect ic;
drv #(9) d(ic);
snk s(ic);
interconnect ia [0:1];
drv #(6) d0(ia[0]);
snk s0(ia[0]);
drv #(3) d1(ia[1]);
snk s1(ia[1]);
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
