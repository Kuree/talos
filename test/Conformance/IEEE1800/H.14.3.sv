// CLAUSE: Source-level compatibility include file svdpi_src.h
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.14.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.14.3: svdpi_src.h declares a 33-bit packed array with SV_BIT_PACKED_ARRAY as 2 canonical words.
// CHECK: words=2

module top;
  import "DPI-C" function int words();
  initial $display("words=%0d", words());
endmodule
