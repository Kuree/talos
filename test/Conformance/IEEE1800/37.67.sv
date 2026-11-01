// CLAUSE: Waits: wait has vpiCondition and vpiStmt, wait_order lists events through vpiCondition with vpiStmt and vpiElseStmt, wait fork
// XFAIL: *
// vpiCondition on vpiOrderedWait returns nothing: the events of wait_order are not retained; wait, wait fork and the actions work.
// RUN: %clang -c -fPIC %S/Inputs/37.67/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiWait condition=a=1 stmt=vpiAssignment
// CHECK-DAG: vpiOrderedWait conditions=first,second, stmt=vpiAssignment else=vpiAssignment
// CHECK-DAG: vpiWaitFork stmt=null
// CHECK: results n=1 p=2

module top;
logic a = 0;
event first, second;
int n, p;
import "DPI-C" context function void probe();
initial begin
  #1 a = 1;
  #1 -> first;
  #1 -> second;
end
initial begin
  wait (a) n = 1;
  wait_order (first, second) p = 2; else p = 3;
  fork #1; join_none
  wait fork;
  probe();
  $display("results n=%0d p=%0d", n, p);
  $finish;
end
endmodule
