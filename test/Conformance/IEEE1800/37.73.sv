// CLAUSE: Expect: vpiExpectStmt gives vpiPropertySpec, the pass action through vpiStmt and the fail action through vpiElseStmt
// XFAIL: *
// vpiPropertySpec is null on vpiExpectStmt; vpiStmt and vpiElseStmt work.
// RUN: %clang -c -fPIC %S/Inputs/37.73/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiExpectStmt property=vpiPropertySpec stmt=n=1 else=m=0
// CHECK-DAG: vpiExpectStmt property=vpiPropertySpec stmt=p=0 else=q=3

module top;
logic c = 0, a = 1;
int n, m, p, q;
import "DPI-C" context function void probe();
always #1 c = ~c;
initial begin
  expect (@(posedge c) a) n = 1; else m = 2;
  expect (@(posedge c) !a) p = 2; else q = 3;
  probe();
  $finish;
end
endmodule
