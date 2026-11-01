// CLAUSE: linkable svDpiVersion
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.14.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.14.1: svDpiVersion() reports exactly one of the two permitted strings, "1800-2005" or "SV3.1a".
// CHECK: known=1 len=9

module top;
  import "DPI-C" function int known();
  import "DPI-C" function int vlen();
  initial $display("known=%0d len=%0d", known(), vlen());
endmodule
