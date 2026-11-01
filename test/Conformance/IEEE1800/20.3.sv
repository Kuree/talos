// CLAUSE: time query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.3: $time is scaled to the time unit of the calling module (10ns units in child, 1ns in top).
// CHECK: child time=3
// CHECK: top time=30

module child;
  timeunit 10ns; timeprecision 1ns;
  initial begin #3; $display("child time=%0d", $time); end
endmodule
module top;
  timeunit 1ns; timeprecision 1ps;
  child c();
  initial begin #30; $display("top time=%0d", $time); end
endmodule
