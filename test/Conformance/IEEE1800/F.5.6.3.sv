// CLAUSE: Vacuity finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// R |-> P is nonvacuous only when R matches. With vacuous passes switched off ($assertvacuousoff, 20.11) the pass
// action counts only tick 1, where the antecedent with its local variable matches, while tick 2's mismatch still fails.
// CHECK: ALL=1101 F=0010
// CHECK: NONVAC=0100 NF=0010

module top;
  bit clk, a; int d, b, t;
  bit [0:3] A = 4'b0110;
  int D[4] = '{9, 2, 3, 9};
  int B[4] = '{0, 2, 0, 0};
  bit [0:3][3:0] ALL, F, NONVAC, NF;
  property p;
    int v;
    (a, v = d) |-> b == v;
  endproperty
  all: assert property (@(posedge clk) p) ALL[t]++; else F[t]++;
  nv: assert property (@(posedge clk) p) NONVAC[t]++; else NF[t]++;
  initial begin
    $assertvacuousoff(0, nv);
    for (t = 0; t < 4; t++) begin
      a = A[t]; d = D[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("ALL=%h F=%h", ALL, F);
    $display("NONVAC=%h NF=%h", NONVAC, NF);
  end
endmodule
