// CLAUSE: $scale optional interface
// XFAIL: *
// $scale(c.t) is rejected by the front end (expected module name); the optional $scale interface is not implemented.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.10: a time of 5 in a 10ns module is 50 in the calling 1ns module.
// CHECK: SCALED=50

module child; timeunit 10ns; timeprecision 1ns; time t = 5; endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  child c();  time scaled;
  initial begin scaled = $scale(c.t); $display("SCALED=%0d", scaled); end
endmodule
