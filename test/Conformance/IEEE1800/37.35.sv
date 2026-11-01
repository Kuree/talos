// CLAUSE: Primitive and prim term: a gate's type, input count, strengths and delays, and each terminal's index, direction and live value
// XFAIL: *
// gate vpiDelay reports rise=0 fall=0 instead of 2 and 3 (terminal values are right)
// RUN: %clang -c -fPIC %S/Inputs/37.35/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiGate name=g
// CHECK: full=top.g
// CHECK: def=nand is_nand=1 inputs=3 strong0=1 pull1=1
// CHECK: delay rise=2 fall=3
// CHECK: t=5
// CHECK-NEXT: term index=0 output=1 value=1
// CHECK-NEXT: term index=1 output=0 value=0
// CHECK-NEXT: term index=2 output=0 value=1
// CHECK-NEXT: term index=3 output=0 value=1
// CHECK-NEXT: primitive value=1
// CHECK: t=6
// CHECK-NEXT: term index=0 output=1 value=1
// CHECK-NEXT: term index=1 output=0 value=1
// CHECK-NEXT: term index=2 output=0 value=1
// CHECK-NEXT: term index=3 output=0 value=1
// CHECK-NEXT: primitive value=1
// CHECK: t=9
// CHECK-NEXT: term index=0 output=1 value=0
// CHECK-NEXT: term index=1 output=0 value=1
// CHECK-NEXT: term index=2 output=0 value=1
// CHECK-NEXT: term index=3 output=0 value=1
// CHECK-NEXT: primitive value=0

// The 3 unit fall delay is what separates t=6 (input 1 already 1, output still 1) from t=9.
`timescale 1ns/1ns
module top;
  logic a = 0, b = 1, c = 1;
  wire y;
  nand (strong0, pull1) #(2, 3) g(y, a, b, c);
  import "DPI-C" context function void describe();
  import "DPI-C" context function void terms();
  initial begin
    describe();
    #5 $display("t=%0t", $time);
    terms();
    a = 1;
    #1 $display("t=%0t", $time);
    terms();
    #3 $display("t=%0t", $time);
    terms();
    $finish;
  end
endmodule
