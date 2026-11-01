// CLAUSE: While, repeat: vpiWhile and vpiRepeat give their loop expression through vpiCondition and their body through vpiStmt
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.66/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiWhile condition=vpiLtOp value=0 body=vpiAssignment lhs=i=3
// CHECK-DAG: vpiRepeat condition=vpiConstant value=4 body=vpiAssignment lhs=j=8

module top;
int i, j;
import "DPI-C" context function void probe();
initial begin
  while (i < 3) i = i + 1;
  repeat (4) j = j + 2;
  probe();
  $finish;
end
endmodule
