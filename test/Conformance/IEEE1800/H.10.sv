// CLAUSE: svdpi.h
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.10/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.10 (svdpi.h): svBitVecVal words are the 32-bit canonical chunks, least significant first.
// CHECK: w0=cdef0123 w1=000000ab

module top;
  import "DPI-C" function int word(input bit [39:0] v, input int i);
  bit [39:0] v = 40'hAB_CDEF_0123;
  initial $display("w0=%h w1=%h", word(v, 0), word(v, 1));
endmodule
