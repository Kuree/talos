// CLAUSE: Instance: vpiInstance gives the immediate instance of any object, vpiModule only inside a module, and instances report vpiTop, lifetime, time units and package-qualified names
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/37.10/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: top type=vpiModule def=top vpiTop=1 auto=0 unit=-9 precision=-12
// CHECK: u type=vpiModule def=leaf vpiTop=0 auto=1 unit=-6 precision=-9
// CHECK: var in module instance=top.u module=top.u
// CHECK: var in program instance=top.p module=null
// CHECK: root top=1 unit=1 pkg=1 extra=1 nested=0
// CHECK-NEXT: unit packages pkg=1 extra=1
// CHECK: package type=vpiPackage full=pkg:: unit=0
// CHECK: var in package full=pkg::pv value=4 instance=pkg::
// CHECK: smallest precision=-12

`timescale 1ns/1ps
package pkg;
int pv;
endpackage
package extra;
int unused;
endpackage
program prog;
int pr;
endprogram
module automatic leaf;
timeunit 1us; timeprecision 1ns;
logic [3:0] s;
endmodule
module top;
timeunit 1ns; timeprecision 1ps;
leaf u();
prog p();
import "DPI-C" context function void probe();
initial begin pkg::pv = 4; probe(); $finish; end
endmodule
