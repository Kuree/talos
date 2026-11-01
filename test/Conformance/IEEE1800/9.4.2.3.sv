// CLAUSE: sequence iff
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 9.4.2.3: the edge at t=1 (en=0) is ignored and the process wakes only at t=3.
// CHECK: WOKE t=3

module top;
  bit clk, en;
  initial begin @(posedge clk iff en); $display("WOKE t=%0t", $time); end
  initial begin #1 clk = 1; #1 clk = 0; en = 1; #1 clk = 1; #1; end
endmodule
