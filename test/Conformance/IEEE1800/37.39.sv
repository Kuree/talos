// CLAUSE: Module path: a specify path gives its full or parallel type, input, output and data terms, edge, condition, polarity and delays
// XFAIL: *
// module path objects are not iterated (no module paths reported)
// RUN: %clang -c -fPIC %S/Inputs/37.39/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: path type=vpiModPath parallel=1 full=0 in=a in_edge=none out=y data=null positive=1 condition=null rise=3 fall=4
// CHECK-DAG: path type=vpiModPath parallel=0 full=1 in=b in_edge=none out=z data=null positive=0 condition=en rise=2 fall=2
// CHECK-DAG: path type=vpiModPath parallel=0 full=1 in=clk in_edge=pos out=q data=d positive=0 condition=null rise=6 fall=6

`timescale 1ns/1ns
module dut(input a, input b, input en, input clk, input d, output y, output z, output q);
  assign y = a;
  assign z = b;
  reg r;
  always @(posedge clk) r <= d;
  assign q = r;
  specify
    (a +=> y) = (3, 4);
    if (en) (b *> z) = 2;
    (posedge clk *> (q : d)) = 6;
  endspecify
endmodule
module top;
  logic a = 0, b = 0, en = 1, clk = 0, d = 0;
  wire y, z, q;
  dut u(a, b, en, clk, d, y, z, q);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
