// CLAUSE: Naming conventions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.3: the C-side name can differ from the SV name, sv-prefixed services (svGetScope, svGetNameFromScope) work, and sv_z/sv_x are 2/3.
// CHECK: f=7 scope=top enc=23

module top;
  import "DPI-C" c_named = function int f();
  import "DPI-C" context function string ctx_name();
  import "DPI-C" function int enc();
  initial $display("f=%0d scope=%s enc=%0d", f(), ctx_name(), enc());
endmodule
