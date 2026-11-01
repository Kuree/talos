// CLAUSE: Instance arrays: an instance array reports its size and bounds, iterates vpiRange from the leftmost dimension and reaches elements by index and multi-index
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.11/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: array type=vpiModuleArray name=u full=top.u size=3 left=3 right=1
// CHECK: by index full=top.u[2] out=2
// CHECK: elements=3
// CHECK: interface array type=vpiInterfaceArray size=2
// CHECK: ranges [1:0] [4:2] left=1 right=0
// CHECK: by multi index full=top.m[0][3] out=7

interface bus; endinterface
module leaf #(parameter int V = 0) (output int out);
assign out = V;
endmodule
module top;
int o[3:1];
leaf #(2) u[3:1](o);
bus b[1:0]();
int om[1:0][4:2];
leaf #(7) m[1:0][4:2](om);
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
