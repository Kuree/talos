// CLAUSE: Derived nonoverlapping implication operator finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// R |=> P is (R ##1 1) |-> P. Consequent true only one tick away from the antecedent's end tells them from |->.
// CHECK: P=1002011 F=0010010 EP=1002011 EF=0010010
// CHECK: LP=1011021 LF=0000100 LEP=1011021 LEF=0000100

module top;
  bit clk, a, b, c; int t;
  bit [0:6] A = 7'b0110100, B = 7'b1101001, C = 7'b0001000;
  bit [0:6][3:0] P, F, EP, EF, LP, LF, LEP, LEF;
  assert property (@(posedge clk) a |=> b) P[t]++; else F[t]++;
  assert property (@(posedge clk) (a ##1 1) |-> b) EP[t]++; else EF[t]++;
  assert property (@(posedge clk) (a ##1 b) |=> c) LP[t]++; else LF[t]++;
  assert property (@(posedge clk) (a ##1 b ##1 1) |-> c) LEP[t]++; else LEF[t]++;
  initial begin
    for (t = 0; t < 7; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P=%h F=%h EP=%h EF=%h", P, F, EP, EF);
    $display("LP=%h LF=%h LEP=%h LEF=%h", LP, LF, LEP, LEF);
  end
endmodule
