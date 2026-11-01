// CLAUSE: Portability
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.7.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.7.2: byte/shortint/longint/real/shortreal/string map to char/short/long long/double/float/const char* and values round-trip.
// CHECK: -2 2000 4294967297 2.50 2.0 5

module top;
  import "DPI-C" function byte b(input byte x);
  import "DPI-C" function shortint s(input shortint x);
  import "DPI-C" function longint l(input longint x);
  import "DPI-C" function real r(input real x);
  import "DPI-C" function shortreal sr(input shortreal x);
  import "DPI-C" function int slen(input string x);
  initial $display("%0d %0d %0d %0.2f %0.1f %0d", b(-3), s(1000), l(64'h1_0000_0000), r(1.25), sr(1.5), slen("hello"));
endmodule
