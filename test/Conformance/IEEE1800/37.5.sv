// CLAUSE: Module: vpi_iterate(vpiModule, NULL) reaches top modules, whose children report names and vpiIndex only inside a module array
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: top type=vpiModule name=top def=top full=top topmodule=1
// CHECK: tops after top=0
// CHECK: child type=vpiModule name=u def=leaf full=top.u topmodule=0 index=null
// CHECK: element full=top.a[1] def=leaf index=1
// CHECK: internal scope=b inside=top.u
// CHECK: port=p contassigns=1

module leaf(input logic p);
wire q;
assign q = p;
if (1) begin : b end
endmodule
module top;
logic x = 1;
leaf u(x);
leaf a[2:1](x);
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
