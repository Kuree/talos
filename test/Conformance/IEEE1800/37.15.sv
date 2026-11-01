// CLAUSE: Reference objects: a ref port, interface port and modport port connect through vpiRefObj handles whose vpiActual is the bound object, net or modport
// XFAIL: *
// vpi_iterate(vpiPort) returns nothing for interface and modport ports, so those vpiRefObj handles cannot be reached, and a task has no io decls to reach a ref formal.
// RUN: %clang -c -fPIC %S/Inputs/37.15/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: ref port low type=vpiRefObj name=r full=top.u1.r generic=-1 actual=top.a actual-type=vpiReg actual-value=5
// CHECK: typespec=vpiLogicTypespec
// CHECK: interface port low type=vpiRefObj name=s generic=0 def=simple actual=top.i actual-type=vpiInterface
// CHECK: interface port high type=vpiRefObj actual=top.i actual-type=vpiInterface
// CHECK: modport high type=vpiRefObj actual-name=initiator actual-type=vpiModport
// CHECK: modport low type=vpiRefObj name=s generic=0 def=initiator actual-name=initiator actual-type=vpiModport
// CHECK: generic low type=vpiRefObj generic=1
// CHECK: task formal type=vpiRefObj name=f

interface simple();
logic req, gnt;
modport target(input req, output gnt);
modport initiator(input gnt, output req);
endinterface
module m(ref logic [2:0] r);
initial r[0] = 1'b1;
endmodule
module child1(simple s); endmodule
module child2(simple.initiator s); endmodule
module child3(interface g); endmodule
module top;
logic [2:0] a = 3'b100;
simple i();
m u1(a);
child1 i1(i);
child2 i2(i.initiator);
child3 i3(i);
task automatic t(ref int f); f = 1; endtask
int z;
import "DPI-C" context function void probe();
initial begin t(z); #1 probe(); $finish; end
endmodule
