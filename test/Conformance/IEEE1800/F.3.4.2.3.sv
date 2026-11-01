// CLAUSE: Derived nonconsecutive repetition operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Every endpoint for one attempt, s@0, with b at 1 3 6 and c at 2 4 5 7 9. b[->m] ends on the m-th b, then c must be
// next. b[=m] adds any run of !b before c, so a third b at 6 ends the b[=2] tail, and b[=2:$] resumes from there.
// CHECK: G2=0000100000 G12=0010100000 G2U=0000100100
// CHECK: N2=0000110000 N12=0010110000 N2U=0000110101

module top;
  bit clk, s, b, c; int t;
  bit [0:9] S = 10'b1000000000, B = 10'b0101001000, C = 10'b0010110101;
  bit [0:9][3:0] G2, G12, G2U, N2, N12, N2U;
  cover sequence (@(posedge clk) s ##1 b[->2] ##1 c) G2[t]++;
  cover sequence (@(posedge clk) s ##1 b[->1:2] ##1 c) G12[t]++;
  cover sequence (@(posedge clk) s ##1 b[->2:$] ##1 c) G2U[t]++;
  cover sequence (@(posedge clk) s ##1 b[=2] ##1 c) N2[t]++;
  cover sequence (@(posedge clk) s ##1 b[=1:2] ##1 c) N12[t]++;
  cover sequence (@(posedge clk) s ##1 b[=2:$] ##1 c) N2U[t]++;
  initial begin
    for (t = 0; t < 10; t++) begin
      s = S[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("G2=%h G12=%h G2U=%h", G2, G12, G2U);
    $display("N2=%h N12=%h N2U=%h", N2, N12, N2U);
  end
endmodule
