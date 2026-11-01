// CLAUSE: Other derived operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// "and" matches at the later end. "within" needs u ##1 v inside c ##3 1, so the attempt at 4 has no match. "throughout"
// loses the match the plain sequence has at tick 6, as g drops at 5. (R, v = e) equals R ##0 (1, v = e), with n captured.
// CHECK: AND=001000000 WITHIN=000100000 THRU=001000000 PLAIN=001000100
// CHECK: L1=010000000 L2=010000000

module top;
  bit clk, a, b, c, d, g, u, v; int n, m, t;
  bit [0:8] A = 9'b100010000, B = 9'b010000100, D = 9'b001000100;
  bit [0:8] G = 9'b111010000, U = 9'b010000000, V = 9'b001000000;
  int N[9] = '{5, 0, 0, 0, 9, 0, 0, 0, 0};
  int M[9] = '{0, 5, 0, 0, 0, 0, 0, 0, 0};
  bit [0:8][3:0] AND, WITHIN, THRU, PLAIN, L1, L2;
  property p1;
    int x;
    (a, x = n) ##1 m == x;
  endproperty
  property p2;
    int x;
    a ##0 (1, x = n) ##1 m == x;
  endproperty
  cover property (@(posedge clk) (a ##1 b) and (a ##2 d)) AND[t]++;
  cover property (@(posedge clk) (u ##1 v) within (a ##3 1)) WITHIN[t]++;
  cover property (@(posedge clk) g throughout (a ##2 d)) THRU[t]++;
  cover property (@(posedge clk) a ##2 d) PLAIN[t]++;
  cover property (@(posedge clk) p1) L1[t]++;
  cover property (@(posedge clk) p2) L2[t]++;
  initial begin
    for (t = 0; t < 9; t++) begin
      a = A[t]; b = B[t]; d = D[t]; g = G[t]; u = U[t]; v = V[t]; n = N[t]; m = M[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("AND=%h WITHIN=%h THRU=%h PLAIN=%h", AND, WITHIN, THRU, PLAIN);
    $display("L1=%h L2=%h", L1, L2);
  end
endmodule
