// CLAUSE: Property specification: a property spec gives its clocking event, disable condition and property expression, whose operator, operands and strength are readable
// XFAIL: *
// property spec objects report spec=null
// RUN: %clang -c -fPIC %S/Inputs/37.52/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: pa spec=vpiPropertySpec event=posedge clk disable=rst expr=vpiOperation
// CHECK-NEXT: overlap_imply=1 nexttime=0
// CHECK-NEXT: operand a
// CHECK-NEXT: operand b
// CHECK-NEXT: operands=2
// CHECK: pn spec=vpiPropertySpec event=negedge clk disable=null expr=vpiOperation
// CHECK-NEXT: overlap_imply=0 nexttime=1 strong=1
// CHECK-NEXT: operand a
// CHECK-NEXT: operands=1
// CHECK: pw spec=vpiPropertySpec event=negedge clk disable=null expr=vpiOperation
// CHECK-NEXT: overlap_imply=0 nexttime=1 strong=0

// Detail 2: a nexttime's constant operand is given only when it differs from 1. Detail 3: s_nexttime is the strong form.
module top;
  logic clk = 0, rst = 0, a = 1, b = 1;
  pa: assert property (@(posedge clk) disable iff (rst) a |-> b);
  pn: assert property (@(negedge clk) s_nexttime a);
  pw: assert property (@(negedge clk) nexttime a);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
