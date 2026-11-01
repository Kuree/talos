// CLAUSE: svdpi.h
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/I.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins Annex I bit/part-select routines: svGetBitselBit, svGetPartselBit (bits 35:28 of ABCDEF0123 = BC = 188), svPutBitselBit and svGetBitselLogic (sv_x=3, sv_z=2).
// CHECK: bits=101 part=188 y=abcdef0127
// CHECK: logic=1302

module top;
  import "DPI-C" function int getb(input bit [39:0] v, input int i);
  import "DPI-C" function int part(input bit [39:0] v);
  import "DPI-C" function void putb(input bit [39:0] v, output bit [39:0] y);
  import "DPI-C" function int lgb(input logic [7:0] v, input int i);
  bit [39:0] v = 40'hAB_CDEF_0123, y;  logic [7:0] lv = 8'b1x0z_0101;
  initial begin
    putb(v, y);
    $display("bits=%0d%0d%0d part=%0d y=%h", getb(v, 0), getb(v, 2), getb(v, 39), part(v), y);
    $display("logic=%0d%0d%0d%0d", lgb(lv, 7), lgb(lv, 6), lgb(lv, 5), lgb(lv, 4));
  end
endmodule
