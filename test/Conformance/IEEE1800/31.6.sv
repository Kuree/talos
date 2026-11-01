// CLAUSE: setup boundary no violation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 31.6: each violation toggles the notifier per the table: x->0, 0->1, 1->0.
// CHECK: n=x 0 1 0

module monitor_t (input wire d, clk, output logic n);
  timeunit 1ns; timeprecision 100ps;
  specify $setup(d, posedge clk, 2, n); endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 100ps;
  logic d = 0, clk = 0;  wire n;  logic s0, s1, s2, s3;
  monitor_t u(d, clk, n);
  initial begin
    #1 s0 = n;
    #4 d = ~d;  #1 clk = 1;  #0.5 s1 = n;  #0.5 clk = 0;
    #4 d = ~d;  #1 clk = 1;  #0.5 s2 = n;  #0.5 clk = 0;
    #4 d = ~d;  #1 clk = 1;  #0.5 s3 = n;
    $display("n=%b %b %b %b", s0, s1, s2, s3);
  end
endmodule
