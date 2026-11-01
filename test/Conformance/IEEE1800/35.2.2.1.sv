// CLAUSE: Data representation
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.2.2.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins 35.2.2.1: svLogicVecVal carries aval/bval (10xz -> aval 0xA, bval 0x3 -> 163), svBit is 0/1, and an output vector round-trips X/Z.
// CHECK: lv=163 bt=10,20 y=01xz

module top;
  import "DPI-C" function int lv(input logic [3:0] x);
  import "DPI-C" function int bt(input bit b);
  import "DPI-C" function void out4(output logic [3:0] y);
  logic [3:0] v = 4'b10xz;  logic [3:0] y;
  initial begin
    out4(y);
    $display("lv=%0d bt=%0d,%0d y=%b", lv(v), bt(1'b1), bt(1'b0), y);
  end
endmodule
