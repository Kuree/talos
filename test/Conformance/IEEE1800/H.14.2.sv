// CLAUSE: svdpi.h definitions for SV3.1a-style packed data processing
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.14.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.14.2: the deprecated SV3.1a macro SV_CANONICAL_SIZE(33) is 2 words.
// CHECK: words=2

module top;
  import "DPI-C" function int words();
  initial $display("words=%0d", words());
endmodule
