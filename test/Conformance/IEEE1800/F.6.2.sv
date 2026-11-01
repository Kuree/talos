// CLAUSE: Derived sampled value functions finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Past with a tick count and a gate over v, at each tick. v is sampled 1 0 1 0 0 1 and en is true at 1, 2, 5. A past
// tick that does not exist evaluates v's initial value, here 1 from the declaration, so G is 1 at ticks 0 and 1.
// CHECK: P1=110100 P2=111010 G=110111 GCLK=110100

module top;
  bit clk, v = 1, en; int t;
  bit [0:5] V = 6'b101001, EN = 6'b011001;
  bit [0:5] P1, P2, G, GCLK;
  global clocking @(posedge clk); endclocking
  cover property (@(posedge clk) $past(v)) P1[t] = 1;
  cover property (@(posedge clk) $past(v, 2)) P2[t] = 1;
  cover property (@(posedge clk) $past(v, 1, en)) G[t] = 1;
  cover property (@($global_clock) $past_gclk(v)) GCLK[t] = 1;
  initial begin
    for (t = 0; t < 6; t++) begin
      v = V[t]; en = EN[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P1=%b P2=%b G=%b GCLK=%b", P1, P2, G, GCLK);
  end
endmodule
