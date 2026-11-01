// CLAUSE: rounded zero vs one step
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.4.2.1: a #1step clocking input samples in the Preponed region, so the value changed in the same time slot (5) is not seen (cb.d=1).
// CHECK: PRE cb.d=1 d=5

module top;
  bit clk;  int d = 1;
  clocking cb @(posedge clk); input #1step d; endclocking
  initial begin #1; d = 5; clk = 1; end
  initial begin @(cb); $display("PRE cb.d=%0d d=%0d", cb.d, d); end
endmodule
