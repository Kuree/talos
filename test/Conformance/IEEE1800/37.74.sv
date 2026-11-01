// CLAUSE: For: vpiForInitStmt and vpiForIncStmt lists, vpiCondition, vpiStmt and vpiLocalVarDecls, with and without a declared loop variable
// XFAIL: *
// vpiCondition is null on a for loop that declares its variable, for (int j = 0; j < 2; ...); a loop over module variables is right.
// RUN: %clang -c -fPIC %S/Inputs/37.74/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiFor local=0 condition=vpiLtOp=0 first_init={{i|k}} init={{i,k,|k,i,}} inc={{i,k,|k,i,}} body=n=6
// CHECK-DAG: vpiFor local=1 condition=vpiLtOp inc=j, body=m=2
// CHECK: loop values i=3 k=6

module top;
int i, k, n, m;
import "DPI-C" context function void probe();
initial begin
  for (i = 0, k = 9; i < 3; i = i + 1, k = k - 1) n = n + 2;
  for (int j = 0; j < 2; j = j + 1) m = j + 1;
  probe();
  $display("loop values i=%0d k=%0d", i, k);
  $finish;
end
endmodule
