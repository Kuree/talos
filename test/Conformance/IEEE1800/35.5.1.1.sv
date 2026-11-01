// CLAUSE: Instant completion of imported functions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.1.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins 35.5.1.1: an imported function completes instantly (no simulation time passes across the call).
// CHECK: f=9 dt=0 t=3

module top;
  import "DPI-C" function int f(input int x);
  int a;  time t0, t1;
  initial begin
    #3; t0 = $time;  a = f(3);  t1 = $time;
    $display("f=%0d dt=%0d t=%0d", a, t1 - t0, $time);
  end
endmodule
