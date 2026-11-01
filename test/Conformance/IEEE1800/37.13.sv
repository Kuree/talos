// CLAUSE: IO declaration: instance and task io decls report direction (vpiRef for ref), name, size, sign and range, and vpiExpr reaches the declared object or ref obj
// XFAIL: *
// vpi_iterate(vpiIODecl, task_or_function) returns NULL, so a task or function has no io decls, even one that is called.
// RUN: %clang -c -fPIC %S/Inputs/37.13/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: io a dir=input size=4 signed=0 scalar=0 vector=1 left=3 right=0 expr=top.u.a value=5
// CHECK-DAG: io b dir=output size=8 signed=1 scalar=0 vector=1 left=7 right=0 expr=top.u.b value=-3
// CHECK-DAG: io c dir=inout size=1 signed=0 scalar=1 vector=0 left=null right=null expr=top.u.c value=1
// CHECK-DAG: io r dir=ref size=8 signed=0 scalar=0 vector=1 left=7 right=0 expr=vpiRefObj
// CHECK-DAG: io x dir=input size=16 signed=0 scalar=0 vector=1 left=15 right=0 expr=top.t.x
// CHECK-DAG: io y dir=output size=1 signed=0 scalar=1 vector=0 left=null right=null expr=top.t.y

module leaf(input logic [3:0] a, output logic signed [7:0] b, inout wire c, ref logic [7:0] r);
assign b = -3;
endmodule
module top;
logic [3:0] a = 5;
wire signed [7:0] b;
wire c = 1;
logic [7:0] r;
leaf u(a, b, c, r);
task t(input bit [15:0] x, output logic y); y = x[0]; endtask
import "DPI-C" context function void probe();
logic got;
initial begin t(16'd3, got); #1 probe(); $finish; end
endmodule
