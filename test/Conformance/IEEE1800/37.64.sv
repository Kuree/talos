// CLAUSE: Assignment: vpiBlocking, vpiOpType (vpiAssignmentOp or the combined operator), vpiLhs, vpiRhs, and delay, event or repeat control
// XFAIL: *
// vpiRhs is null on a compound assignment such as a += 2; vpiOpType and every other assignment's vpiRhs and control are right.
// RUN: %clang -c -fPIC %S/Inputs/37.64/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiAssignment blocking=1 op=vpiAssignmentOp lhs=a=7 rhs=5 control=none
// CHECK-DAG: vpiAssignment blocking=0 op=vpiAssignmentOp lhs=b=6 rhs=6 control=none
// CHECK-DAG: vpiAssignment blocking=1 op=vpiAddOp lhs=a=7 rhs=2 control=none
// CHECK-DAG: vpiAssignment blocking=1 op=vpiAssignmentOp lhs=d=8 rhs=8 control=vpiDelayControl
// CHECK-DAG: vpiAssignment blocking=0 op=vpiAssignmentOp lhs=e=9 rhs=9 control=vpiEventControl
// CHECK-DAG: vpiAssignment blocking=1 op=vpiAssignmentOp lhs=r=3 rhs=3 control=vpiRepeatControl

module top;
int a, b, d, e, r;
event go;
import "DPI-C" context function void probe();
always #2 -> go;
initial begin
  a = 5;
  b <= 6;
  a += 2;
  d = #1 8;
  e <= @go 9;
  r = repeat (2) @go 3;
  #2 probe();
  $finish;
end
endmodule
