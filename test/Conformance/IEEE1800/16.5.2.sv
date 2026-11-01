// CLAUSE: boolean control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Figure 16-1: a variable that changes in a tick's time step is sampled at its old value. The clock
// expression uses the current value, so clk is sampled 0 at its own rising edge, and "iff" gates the tick.
// CHECK: HI=0101 LO=1010 OWN=1111 NEG=1111 GATED=0101

module top;
  bit clk, req, en; int t;
  bit [0:3] R = 4'b1011, E = 4'b0101;
  bit [0:3][3:0] HI, LO, OWN, NEG, GATED;
  assert property (@(posedge clk) req) HI[t]++; else LO[t]++;
  assert property (@(posedge clk) clk) $fatal(1, "clk sampled high at its rising edge"); else OWN[t]++;
  assert property (@(negedge clk) clk) NEG[t]++; else $fatal(1, "clk sampled low at its falling edge");
  assert property (@(posedge clk iff en) 1'b1) GATED[t]++;
  initial begin
    for (t = 0; t < 4; t++) begin
      #1 req = R[t]; en = E[t]; clk = 1;
      #1 clk = 0;
      #1;
    end
    $display("HI=%h LO=%h OWN=%h NEG=%h GATED=%h", HI, LO, OWN, NEG, GATED);
  end
endmodule
