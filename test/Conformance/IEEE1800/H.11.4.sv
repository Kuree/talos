// CLAUSE: Direct access to unpacked arrays
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.11.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.11.4: a sized unpacked formal is passed as a plain C array that C indexes directly, in both directions.
// CHECK: f=45 g=7,8

module top;
  import "DPI-C" function int f(input int a[2]);
  import "DPI-C" function void g(output int a[2]);
  int a[2] = '{4, 5};  int o[2];
  initial begin g(o); $display("f=%0d g=%0d,%0d", f(a), o[0], o[1]); end
endmodule
