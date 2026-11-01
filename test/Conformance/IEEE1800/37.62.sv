// CLAUSE: Event statement: -> and ->> are vpiEventStmt with vpiBlocking and a vpiNamedEvent relation to the event
// XFAIL: *
// vpiBlocking is undefined and vpiNamedEvent is null on vpiEventStmt; the statement's event and its blocking kind are not retained.
// RUN: %clang -c -fPIC %S/Inputs/37.62/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiEventStmt blocking=1 event=go
// CHECK-DAG: vpiEventStmt blocking=0 event=later
// CHECK: triggered: go=1 later=1

module top;
event go, later;
int gos, laters;
import "DPI-C" context function void probe();
always @go gos++;
always @later laters++;
initial begin
  #1 -> go;
  ->> later;
  #1 probe();
  $display("triggered: go=%0d later=%0d", gos, laters);
  $finish;
end
endmodule
