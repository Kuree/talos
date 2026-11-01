// CLAUSE: Portability
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.4: an object built by the host C compiler links into the simulation and int/double/char arguments cross the boundary.
// CHECK: add3=6 half=2.50 byte=-3

module top;
  import "DPI-C" function int add3(input int a, input int b, input int c);
  import "DPI-C" function real half(input real x);
  import "DPI-C" function int bval(input byte x);
  initial $display("add3=%0d half=%0.2f byte=%0d", add3(1, 2, 3), half(5.0), bval(-3));
endmodule
