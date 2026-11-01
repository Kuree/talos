// CLAUSE: Variable drivers and loads: vpiDriver and vpiLoad on a variable return the continuous assignments that drive and read it
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.21/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: drivers=1 driver type=vpiContAssign lhs=top.v rhs=1
// CHECK: loads=1 load type=vpiContAssign lhs=top.l rhs=1
// CHECK: undriven drivers=0 unread loads=0

module top;
logic a = 1;
var logic v;
assign v = a;
var logic l;
assign l = v;
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
