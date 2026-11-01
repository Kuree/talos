// CLAUSE: checker ff assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 17.7.3: the checker nonblocking update lands in Re-NBA, after the Reactive observer of the module NBA saw the old v (v=0), and before the next tick (v=1).
// CHECK-DAG: TICK v=0
// CHECK-DAG: OBS mm=1 v=0
// CHECK: TICK v=1

checker c(input event clock, input logic mm);
  int v = 0;
  always_ff @clock begin $display("TICK v=%0d", v); v <= v + 1; end
  always_ff @(mm) $display("OBS mm=%0d v=%0d", mm, v);
endchecker
module top;
  bit clk, m;
  always @(posedge clk) m <= 1;
  c inst(posedge clk, m);
  initial begin #1 clk = 1; #1 clk = 0; #1 clk = 1; end
endmodule
