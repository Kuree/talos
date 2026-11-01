// CLAUSE: checker ff assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 17.7.1: a nonblocking assignment to a checker variable in always_ff takes effect before the next tick (dropping it prints v=0 three times).
// CHECK: v=0
// CHECK: v=1
// CHECK: v=2

checker c(input event clock);
  int v = 0;
  always_ff @clock begin $display("v=%0d", v); v <= v + 1; end
endchecker
module top;
  bit clk;  c inst(posedge clk);
  initial begin repeat (3) begin #1 clk = 1; #1 clk = 0; end end
endmodule
