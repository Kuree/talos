// CLAUSE: cbStmt by statement type: a for fires before its controls and per increment, an if before its condition, delay and event controls before they wait
// XFAIL: *
// vpi_register_cb rejects cbStmt with "reason is not implemented" (docs/vpi.md: cbStmt dispatch is not yet implemented).
// RUN: %clang -c -fPIC %S/Inputs/38.36.1.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: statements=4 registered=4
// CHECK-NEXT: vpiFor t=1 x=0
// CHECK-NEXT: vpiFor t=1 x=1
// CHECK-NEXT: vpiFor t=1 x=2
// CHECK-NEXT: vpiFor t=1 x=3
// CHECK-NEXT: vpiIf t=1 x=3
// CHECK-NEXT: vpiDelayControl t=1 x=10
// CHECK-NEXT: vpiEventControl t=3 x=10
// CHECK-NEXT: after t=5

module top;
timeunit 1ns; timeprecision 1ns;
int x = 0;
event e;
import "DPI-C" context function void setup();
initial begin
  setup();
  #1;
  begin : body
    for (int i = 0; i < 3; i++) x += 1;
    if (x == 3) x = 10;
    #2;
    @(e);
  end
  $display("after t=%0t", $time);
  $finish;
end
initial #5 -> e;
endmodule
