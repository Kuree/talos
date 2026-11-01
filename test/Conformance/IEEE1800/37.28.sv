// CLAUSE: Parameter, spec param, def param, param assign: values are the elaborated ones while vpiExpr keeps the default, and param assign, def param and spec param objects report their sides
// XFAIL: *
// Only partly implemented: vpiExpr reports the default of a value parameter unavailable, real parameters and spec params are not found, and vpiDefParam returns NULL (docs/vpi.md admits nonpacked parameters and defparam).
// RUN: %clang -c -fPIC %S/Inputs/37.28/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: P type=vpiParameter full=top.u.P value=9 default=7 size=32 signed=1 local=0 left=null
// CHECK: Q type=vpiParameter full=top.u.Q value=2 default=2 size=4 signed=0 local=0 left=3
// CHECK: L type=vpiParameter value=10 local=1
// CHECK: real const=1 value=2.5
// CHECK: type param type=vpiTypeParameter typespec=vpiByteTypespec default=vpiLogicTypespec
// CHECK: param assign lhs=top.u.P rhs=9 byname=1
// CHECK: param assign lhs=top.u.T typespec=vpiByteTypespec byname=1
// CHECK: def param type=vpiDefParam lhs=top.v.Q rhs=12 elaborated=12
// CHECK: spec param type=vpiSpecParam value=3

module leaf #(parameter int P = 7, parameter logic [3:0] Q = 2, parameter real R = 2.5, parameter type T = logic) ();
localparam int L = P + 1;
specify
  specparam sp = 3;
endspecify
T carried;
endmodule
module top;
leaf #(.P(9), .T(byte)) u();
leaf v();
defparam v.Q = 12;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
