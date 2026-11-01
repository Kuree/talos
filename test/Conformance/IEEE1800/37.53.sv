// CLAUSE: Sequence declaration: a sequence decl gives its name, formals in order with direction, type and default, its local variables and its expression
// XFAIL: *
// sequence declarations report expr=null
// RUN: %clang -c -fPIC %S/Inputs/37.53/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: decl type=vpiSequenceDecl name=s
// CHECK: full=top.s
// CHECK-NEXT: formal x nodir=1 input=0 typed=0 default=null
// CHECK-NEXT: formal y nodir=1 input=0 typed=1 default=2
// CHECK-NEXT: formal z nodir=0 input=1 typed=1 default=5
// CHECK-NEXT: variable v
// CHECK-NEXT: expr=vpiOperation cycle_delay=1

// Detail 4: only z is a local variable argument, and it is an input. Detail 2: x is untyped.
module top;
  logic clk = 0, a = 1;
  sequence s(x, int y = 2, local input int z = 5);
    int v;
    (x, v = y + z) ##1 (v > 0);
  endsequence
  cs: cover sequence (@(posedge clk) s(a));
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
