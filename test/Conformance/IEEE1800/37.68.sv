// CLAUSE: Delay control: vpiDelay and vpi_get_delays give the delay, vpiStmt the controlled statement, NULL when on an assignment
// XFAIL: *
// vpiDelay is null on a delay control, and vpi_get_delays reports that delay metadata is unavailable (it covers nets and intermodule paths only).
// RUN: %clang -c -fPIC %S/Inputs/37.68/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiDelayControl delay=3 get_delays=3 stmt=vpiAssignment
// CHECK-DAG: assignment control=vpiDelayControl delay=2 get_delays=2 stmt=null
// CHECK: results n=1 m=5 at 5

module top;
timeunit 1ns; timeprecision 1ns;
int n, m;
import "DPI-C" context function void probe();
initial begin
  #3 n = 1;
  m = #2 5;
  probe();
  $display("results n=%0d m=%0d at %0t", n, m, $time);
  $finish;
end
endmodule
