// CLAUSE: time query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.3.1: $time rounds to the module time unit (2.6 -> 3) while $realtime keeps the fraction.
// CHECK: time=3 realtime=2.600

module top;
  timeunit 1ns; timeprecision 1ps;
  time t;  realtime rt;
  initial begin
    #2.6; t = $time; rt = $realtime;
    $display("time=%0d realtime=%0.3f", t, rt);
  end
endmodule
