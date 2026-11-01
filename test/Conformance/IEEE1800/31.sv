// CLAUSE: Timing checks
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins clause 31: a timing check that sees a violating pulse toggles its notifier and a compliant one does not.
// CHECK: n=110

module monitor_t (input wire clk, output logic n = 0);
  timeunit 1ns; timeprecision 100ps;
  specify $width(posedge clk, 3, 0, n); endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 100ps;
  logic clk = 0;  wire n;  logic s1, s2, s3;
  monitor_t u(clk, n);
  initial begin
    #5 clk = 1;  #1 clk = 0;  #0.5 s1 = n;      // pulse of width 1 < 3: violation
    #3.5 clk = 1;  #4 clk = 0;  #0.5 s2 = n;    // pulse of width 4: no violation
    #5.5 clk = 1;  #1 clk = 0;  #0.5 s3 = n;    // pulse of width 1: violation again
    $display("n=%b%b%b", s1, s2, s3);
  end
endmodule
