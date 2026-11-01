// CLAUSE: Nets: a net reports type, size and net type, follows its drivers over time, resolves wired logic, and exposes net bits, array members and implicit declarations
// XFAIL: *
// An implicit net reports vpiLineNo 22, its first reference, where detail 9 requires 0.
// RUN: %clang -c -fPIC %S/Inputs/37.16/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: w type=vpiNet size=4 nettype=vpiWire scalar=0 vector=1 implicit=0 value=5
// CHECK: w value=10
// CHECK: bits=4 bit type=vpiNetBit full=top.w[3] parent=top.w index=3 value=1
// CHECK: wired and nettype=vpiWand value=0
// CHECK: array type=vpiNetArray size=3 member=1 top.arr[1] value=2
// CHECK: implicit type=vpiNet implicit=1 line=0 value=1

module top;
logic [3:0] d = 4'h5;
wire [3:0] w;
assign w = d;
wand both;
assign both = 1'b1;
assign both = 1'b0;
wire [1:0] arr [2:0];
assign arr[1] = 2'd2;
assign made_up = d[1];
import "DPI-C" context function void first();
import "DPI-C" context function void second();
initial begin
  #1 first();
  d = 4'hA;
  #1 second();
  $finish;
end
endmodule
