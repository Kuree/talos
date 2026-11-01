// CLAUSE: Future finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// $future_gclk(e) at tick j is e at tick j+1, so the attempt at each tick reports on the next tick, with the sampled
// value there compared. On the last tick the value is undefined and no result is claimed.
// CHECK: T=011010 F=000101

module top;
  bit clk, v; int t;
  bit [0:5] V = 6'b011010, T, F;
  global clocking @(posedge clk); endclocking
  assert property (@($global_clock) $future_gclk(v)) begin if (t < 6) T[t] = 1; end else if (t < 6) F[t] = 1;
  initial begin
    for (t = 0; t < 6; t++) begin
      v = V[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("T=%b F=%b", T, F);
  end
endmodule
