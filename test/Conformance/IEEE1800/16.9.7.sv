// CLAUSE: sequence or
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// The match set of "or" is the union: attempt 0 has endpoints at ticks 1 and 2, attempt 3 only the right one
// at tick 5, and attempt 6 fails only when both operands have failed, at tick 8.
// CHECK: FIRST=0100010000 ALL=0110010000 F=0000000010

module top;
  bit clk, s, a, b, c, d; int t;
  bit [0:9] S = 10'b1001001000, B = 10'b0100000000, D = 10'b0010010000;
  bit [0:9][3:0] FIRST, ALL, F;
  cover property (@(posedge clk) (a ##1 b) or (c ##2 d)) FIRST[t]++;
  cover sequence (@(posedge clk) (a ##1 b) or (c ##2 d)) ALL[t]++;
  assert property (@(posedge clk) s |-> (a ##1 b) or (c ##2 d)) else F[t]++;
  initial begin
    for (t = 0; t < 10; t++) begin
      s = S[t]; a = S[t]; c = S[t]; b = B[t]; d = D[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("FIRST=%h ALL=%h F=%h", FIRST, ALL, F);
  end
endmodule
