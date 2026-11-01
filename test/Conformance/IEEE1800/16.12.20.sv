// CLAUSE: bounded temporal property example
// XFAIL: *
// Most of the clause's example properties are rejected: "not" of a sequence in a consequent, implication nested in and/or, and a goto antecedent with a temporal consequent.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// The clause's rules on one trace. R1P and R2P include a vacuous pass per tick with a false a. rule1 passes at tick 2 and
// 23 and breaks at 5, 9, 10, 15, 16. rule2 is its negation, with attempt 21 cancelled by e at tick 22. a[*2] holds for
// attempts 9 and 15: rule3 fails only at 19 when both alternatives are dead, rule4 at 11 and 17 on the first dead one.
// rule5 fails at 7 on (d |-> e) after b, and twice at 13 on f after c.
// CHECK: R1P=012101111001111001111012 R1F=000001000110000110000000
// CHECK: R2P=011102111111111111111001 R2F=001000000000000000000000
// CHECK: R3F=000000000000000000010000
// CHECK: R4F=000000000001000001000000
// CHECK: R5F=000000010000020000000000

module top;
  bit clk, a, b, c, d, e, f; int t;
  bit [0:23] A = 24'b100010000110000110000100, B = 24'b100010100000000000000100;
  bit [0:23] C = 24'b010000000000010000000010, D = 24'b001000010010000010000001;
  bit [0:23] E = 24'b000000000000000000000010, FF = 24'b010000000000000000000010;
  bit [0:23][3:0] R1P, R1F, R2P, R2F, R3F, R4F, R5F;
  property rule1;
    @(posedge clk) a |-> b ##1 c ##1 d;
  endproperty
  property rule2;
    @(posedge clk) disable iff (e) a |-> not(b ##1 c ##1 d);
  endproperty
  property rule3;
    @(posedge clk) a[*2] |-> ((##[1:3] c) or (d |=> e));
  endproperty
  property rule4;
    @(posedge clk) a[*2] |-> ((##[1:3] c) and (d |=> e));
  endproperty
  property rule5;
    @(posedge clk) a ##1 (b || c)[->1] |-> if (b) (##1 d |-> e) else f;
  endproperty
  assert property (rule1) R1P[t]++; else R1F[t]++;
  assert property (rule2) R2P[t]++; else R2F[t]++;
  assert property (rule3) else R3F[t]++;
  assert property (rule4) else R4F[t]++;
  assert property (rule5) else R5F[t]++;
  initial begin
    for (t = 0; t < 24; t++) begin
      a = A[t]; b = B[t]; c = C[t]; d = D[t]; e = E[t]; f = FF[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("R1P=%h R1F=%h", R1P, R1F);
    $display("R2P=%h R2F=%h", R2P, R2F);
    $display("R3F=%h", R3F);
    $display("R4F=%h", R4F);
    $display("R5F=%h", R5F);
  end
endmodule
