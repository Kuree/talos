// CLAUSE: Alias statement: alias a=b=c=d yields three vpiAliasStmt objects of the instance, each with d as vpiRhs, and the nets share one value
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.76/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: vpiAliasStmt lhs=a=1 rhs=d=1
// CHECK-DAG: vpiAliasStmt lhs=b=1 rhs=d=1
// CHECK-DAG: vpiAliasStmt lhs=c=1 rhs=d=1
// CHECK: aliases=3

module top;
wire a, b, c, d;
alias a = b = c = d;
assign d = 1;
import "DPI-C" context function void probe();
initial begin
  #1 probe();
  $finish;
end
endmodule
