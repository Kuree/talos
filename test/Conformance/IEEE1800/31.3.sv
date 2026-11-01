// CLAUSE: setup boundary no violation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 31.3: $hold reports only when a data change follows the reference edge by less than the limit (boundary and far cases are clean).
// CHECK: n=1100

module monitor_t (input wire d, clk, output logic n = 0);
  timeunit 1ns; timeprecision 100ps;
  specify $hold(posedge clk, d, 2, n); endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 100ps;
  logic d = 0, clk = 0;  wire n;  logic s1, s2, s3, s4;
  monitor_t u(d, clk, n);
  initial begin
    #5 clk = 1;  #1 d = 1;  #0.5 s1 = n;  #0.5 clk = 0;   // data 1 after the edge: violation, n 0->1
    #3 clk = 1;  #1 clk = 0;  #1 d = 0;  #0.5 s2 = n;     // data 2 after the edge: exactly the limit, no violation
    #1.5 clk = 1;  #1 d = 1;  #0.5 s3 = n;  #0.5 clk = 0; // 1 after the edge: violation, n 1->0
    #4 clk = 1;  #6 d = 0;  #0.5 s4 = n;                  // 6 after the edge: no violation
    $display("n=%b%b%b%b", s1, s2, s3, s4);
  end
endmodule
