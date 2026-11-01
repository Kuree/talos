// CLAUSE: Assertion uses the clocking input sample
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.18/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: requires a clocking block input used in a concurrent assertion to have #1step sampling
// CHECK: passes=1 failures=1

// 16.18 samples a clocking variable only in its clocking block, and 16.5.1 makes
// that #1step sampling: the first tick sees 0, before the tick's own NBA.
module top;
  bit clk = 0, data = 0;
  int passes = 0, failures = 0;
  always @(posedge clk) data <= 1;
  clocking cb @(posedge clk); input #1step data; endclocking
  a: assert property (@(posedge clk) cb.data) passes++; else failures++;
  initial begin
    repeat (2) begin #1 clk = 1; #1 clk = 0; end
    #1 $display("passes=%0d failures=%0d", passes, failures);
    $finish;
  end
endmodule
