// CLAUSE: Do-while, foreach: vpiDoWhile condition and body; vpiForeachStmt vpiVariables array and vpiLoopVars with vpiNullOp for a skipped index
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.75/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiDoWhile condition=vpiLtOp=0 stmt=n=3
// CHECK-DAG: vpiForeachStmt array=g vars=a,b, stmt=t=6
// CHECK-DAG: vpiForeachStmt array=g vars=skipped,y, stmt=w=3

module top;
int n, t, w, g[2][3];
import "DPI-C" context function void probe();
initial begin
  do n = n + 1; while (n < 3);
  foreach (g[a, b]) t = t + 1;
  foreach (g[, y]) w = w + 1;
  probe();
  $finish;
end
endmodule
