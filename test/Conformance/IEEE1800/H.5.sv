// CLAUSE: svdpi.h
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.5: svdpi.h scalar encoding of logic (sv_0..sv_x = 0,1,2,3) and the canonical 32-bit word split of a 40-bit packed bit vector.
// CHECK: enc=0123 words=cdef0123,000000ab

module top;
  import "DPI-C" function int enc(input logic b);
  import "DPI-C" function int bits(input bit [39:0] v, input int word);
  bit [39:0] v = 40'hAB_CDEF_0123;
  initial $display("enc=%0d%0d%0d%0d words=%h,%h", enc(1'b0), enc(1'b1), enc(1'bz), enc(1'bx), bits(v, 0), bits(v, 1));
endmodule
