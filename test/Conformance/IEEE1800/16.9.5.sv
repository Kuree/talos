// CLAUSE: sequence and
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Attempt 0 matches at the later operand end, tick 2, whichever operand is longer. Attempt 4 fails on the
// left operand and attempt 8 on the right one.
// CHECK: L=001000000000 R=001000000000 f=2

module top;
  bit clk, s, a, b, c, d; int t, f;
  bit [0:11] S = 12'b100010001000, B = 12'b010000000100, D = 12'b001000100000;
  bit [0:11][3:0] L, R;
  cover property (@(posedge clk) (a ##1 b) and (c ##2 d)) L[t]++;
  cover property (@(posedge clk) (c ##2 d) and (a ##1 b)) R[t]++;
  assert property (@(posedge clk) s |-> (a ##1 b) and (c ##2 d)) else f++;
  initial begin
    for (t = 0; t < 12; t++) begin
      s = S[t]; a = S[t]; c = S[t]; b = B[t]; d = D[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("L=%h R=%h f=%0d", L, R, f);
  end
endmodule
