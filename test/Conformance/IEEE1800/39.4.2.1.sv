// CLAUSE: A callback on an assertion with a global clocking future function runs at the next global clock tick, with cb_time still the event's time
// XFAIL: *
// The runtime has no vpi_register_assertion_cb (undefined symbol at link), and the compiler rejects the clause's example properties: global-future functions need a one-cycle property.
// RUN: %clang -c -fPIC %S/Inputs/39.4.2.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: registered=2
// CHECK-DAG: a1 kill ran=12 cb_time=11
// CHECK-DAG: a2 kill ran=12 cb_time=11

module top;
timeunit 1ns; timeprecision 1ns;
logic gclk = 1, clk = 0, a = 1, b = 1;
always #1 gclk = ~gclk; // rises at 2, 4, ... 10, 12
global clocking @(posedge gclk); endclocking
// The clause's example: attempts start at 10, and $assertkill at 11 falls before the global clock tick at 12.
a1: assert property (@(posedge clk) $falling_gclk(a) |=> b);
a2: assert property (@(posedge clk) a |=> $falling_gclk(b));
import "DPI-C" context function void setup();
initial begin
  setup();
  #10 clk = 1;
  #1 $assertkill;
  #5 $finish;
end
endmodule
