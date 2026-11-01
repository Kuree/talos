// CLAUSE: Portability
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.10.1.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.10.1.3: svDpiVersion() returns "1800-2005" for the VPI-based canonical representation.
// CHECK: VER=1800-2005

module top;
  import "DPI-C" function string ver();
  initial $display("VER=%s", ver());
endmodule
