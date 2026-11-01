// CLAUSE: stime query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.3.2: $stime is the low 32 bits of the time (2**32+5 -> 5) while $time is 64-bit.
// CHECK: time=4294967301 stime=5

module top;
  timeunit 1ns; timeprecision 1ps;
  time t;  int s;
  initial begin
    #4294967301; t = $time; s = $stime;
    $display("time=%0d stime=%0d", t, s);
  end
endmodule
