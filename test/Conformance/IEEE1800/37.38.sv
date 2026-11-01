// CLAUSE: Constraint expression: implication, if and if-else items give their conditions and branches in order, and a soft expression is marked soft
// XFAIL: *
// constraint items are not iterated (no constraint items reported)
// RUN: %clang -c -fPIC %S/Inputs/37.38/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: item vpiImplication
// CHECK-NEXT: condition mode
// CHECK-NEXT: expr a == 1
// CHECK-NEXT: item vpiConstrIfElse
// CHECK-NEXT: condition mode
// CHECK-NEXT: expr b < 5
// CHECK-NEXT: else b > 10
// CHECK-NEXT: item vpiConstrIf
// CHECK-NEXT: condition a == 0
// CHECK-NEXT: expr b == 3
// CHECK-NEXT: item vpiOperation
// CHECK-NEXT: soft=1 a == 2

module top;
  class C;
    rand bit mode;
    rand int a, b;
    constraint c {
      mode -> a == 1;
      if (mode) b < 5; else b > 10;
      if (a == 0) b == 3;
      soft a == 2;
    }
  endclass
  C o;
  import "DPI-C" context function void probe();
  initial begin o = new; probe(); $finish; end
endmodule
