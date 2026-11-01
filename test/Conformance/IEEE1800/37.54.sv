// CLAUSE: Sequence expression: operations give their type and operands in the clause's order, and a sequence inst gives its decl and arguments
// XFAIL: *
// sequence expression objects report top=null
// RUN: %clang -c -fPIC %S/Inputs/37.54/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: top=vpiOperation intersect=1
// CHECK-NEXT: operand0=vpiSequenceInst decl=s
// CHECK-NEXT: arg a
// CHECK-NEXT: arg b
// CHECK-NEXT: operand1=vpiOperation cycle_delay=1
// CHECK-NEXT: delay a
// CHECK-NEXT: delay b
// CHECK-NEXT: delay 1
// CHECK-NEXT: delay 2
// CHECK-NEXT: delay operands=4
// CHECK: repeat=vpiOperation consecutive=1
// CHECK-NEXT: operand a
// CHECK-NEXT: operand 3
// CHECK-NEXT: repeat operands=2

// Details 1 and 3: ## with a range lists both sequences then both bounds; [*3] has one bound as its right bound equals its left.
module top;
  logic clk = 0, a = 1, b = 1;
  sequence s(x, y);
    x ##1 y;
  endsequence
  c_int: cover sequence (@(posedge clk) s(a, b) intersect (a ##[1:2] b));
  c_rep: cover sequence (@(posedge clk) a[*3]);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
