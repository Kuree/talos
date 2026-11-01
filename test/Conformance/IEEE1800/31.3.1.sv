// CLAUSE: setup boundary no violation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 31.3.1: $setup reports only when the data-to-edge interval is below the limit, so the exact-limit and far cases leave the notifier alone.
// CHECK: n=1100

module monitor_t (input wire d, clk, output logic n = 0);
  timeunit 1ns; timeprecision 100ps;
  specify $setup(d, posedge clk, 2, n); endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 100ps;
  logic d = 0, clk = 0;  wire n;  logic s1, s2, s3, s4;
  monitor_t u(d, clk, n);
  initial begin
    #5 d = 1;  #1 clk = 1;  #0.5 s1 = n;  #0.5 clk = 0;   // data 1 before the edge: violation, n 0->1
    #3 d = 0;  #2 clk = 1;  #0.5 s2 = n;  #0.5 clk = 0;   // exactly the limit (2): no violation
    #1 d = 1;  #1 clk = 1;  #0.5 s3 = n;  #0.5 clk = 0;   // 1 before the edge: violation, n 1->0
    #4 d = 0;  #5 clk = 1;  #0.5 s4 = n;                  // 5 before the edge: no violation
    $display("n=%b%b%b%b", s1, s2, s3, s4);
  end
endmodule
