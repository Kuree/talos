// CLAUSE: Event control: vpiCondition gives the edge or named event, vpiStmt the controlled statement, NULL when on an assignment
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.65/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiEventControl condition=vpiOperation op=posedge operand=c stmt=vpiAssignment lhs=n=1
// CHECK-DAG: vpiEventControl condition=vpiNamedEvent name=go stmt=vpiAssignment lhs=m=2
// CHECK-DAG: assignment control=vpiEventControl condition=vpiOperation op=negedge operand=c stmt=null lhs=p=3
// CHECK: time=5

module top;
logic c = 0;
event go;
int n, m, p;
import "DPI-C" context function void probe();
always #2 c = ~c;
initial #3 -> go;
initial begin
  @(posedge c) n = 1;
  @go m = 2;
  p = @(negedge c) 3;
  #1 probe();
  $display("time=%0t", $time);
  $finish;
end
endmodule
