// CLAUSE: Continuous assignment: vpiContAssign gives Lhs and Rhs, net-declaration flag, strengths, delay, the delayed value, and its bits by offset from the LSB
// XFAIL: *
// continuous assignment bits report lhs=null and rhs=null, and a net reports value=z
// RUN: %clang -c -fPIC %S/Inputs/37.47/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: lhs=w rhs=a & b decl=0 strong0=1 pull1=1 delay=2 vpiDelay=2
// CHECK-DAG: lhs=n rhs=a decl=1 strong0=1 pull1=0 delay=0 vpiDelay=none
// CHECK-DAG: lhs=v rhs={{.*}}b{{.*}}3'b101{{.*}} decl=0 strong0=1 pull1=0 delay=0 vpiDelay=none
// CHECK: bit type=vpiContAssignBit offset=0 size=1
// CHECK: bit type=vpiContAssignBit offset=1 size=1
// CHECK: bit type=vpiContAssignBit offset=2 size=1
// CHECK: bit type=vpiContAssignBit offset=3 size=1
// CHECK: t=2 w=0 value=0
// CHECK: t=4 w=1 value=1
// CHECK: bit offset=0 value=1
// CHECK: bit offset=1 value=0
// CHECK: bit offset=2 value=1
// CHECK: bit offset=3 value=1

// w's assignment has a delay of 2 and a changes at t=1, so at t=2 its value is still the old one.
`timescale 1ns/1ns
module top;
  logic a = 0, b = 1;
  wire n = a;
  wire w;
  wire [3:0] v;
  assign (strong0, pull1) #2 w = a & b;
  assign v = {b, 3'b101};
  import "DPI-C" context function void describe();
  import "DPI-C" context function void values(int t);
  initial begin
    describe();
    #1 a = 1;
    #1 values($time);
    #2 values($time);
    $finish;
  end
endmodule
