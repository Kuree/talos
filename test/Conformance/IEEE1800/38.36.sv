// CLAUSE: vpi_register_cb returns a callback handle and calls cb_rtn at the point its reason selects, with reason, time and user_data in a new s_cb_data
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.36/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: handle=vpiCallback
// CHECK-NEXT: cbAfterDelay now=3 time=3 user=three new=1
// CHECK-NEXT: active t=7
// CHECK-NEXT: cbReadOnlySynch now=7 time=7 user=seven new=1
// CHECK-NEXT: cbEndOfSimulation now=9 user=end new=1

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" context function void setup();
initial begin
  setup();
  #7 $display("active t=%0t", $time);
  #2 $finish;
end
endmodule
