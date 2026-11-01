// CLAUSE: If, if-else: vpiIf and vpiIfElse give vpiCondition, vpiStmt, vpiElseStmt and vpiQualifier for plain, unique and priority forms
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.71/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// The value printed with each branch's target shows which branch ran.
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiIf qualifier=none condition=vpiReg=1 stmt=n=1 else=null
// CHECK-DAG: vpiIfElse qualifier=unique condition=vpiOperation=0 stmt=p=0 else=q=3
// CHECK-DAG: vpiIfElse qualifier=priority condition=vpiReg=1 stmt=r=4 else=s=0

module top;
logic a = 1;
int n, p, q, r, s;
import "DPI-C" context function void probe();
initial begin
  if (a) n = 1;
  unique if (!a) p = 2; else q = 3;
  priority if (a) r = 4; else s = 5;
  probe();
  $finish;
end
endmodule
