// CLAUSE: Delay terminals: a module path's delay device has input and output delay terms; the input term changes before the delay and the output term only after it
// XFAIL: *
// module path objects report device=null and modpath=0
// RUN: %clang -c -fPIC %S/Inputs/37.45/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: device=vpiDelayDevice modpath=1
// CHECK: in=vpiDelayTerm modpath=1
// CHECK: out=vpiDelayTerm modpath=1
// CHECK: t=2 in=1 out=0
// CHECK: t=6 in=1 out=1

// Details 1 and 2: the path delay of 5 applies from t=1, so t=2 falls inside the delay and t=6 after it.
`timescale 1ns/1ns
module dut(input a, output y);
  assign y = a;
  specify
    (a => y) = 5;
  endspecify
endmodule
module top;
  logic a = 0;
  wire y;
  dut u(a, y);
  import "DPI-C" context function void describe();
  import "DPI-C" context function void values(int t);
  initial begin
    describe();
    #1 a = 1;
    #1 values($time);
    #4 values($time);
    $finish;
  end
endmodule
