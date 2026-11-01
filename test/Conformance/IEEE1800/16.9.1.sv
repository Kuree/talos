// CLAUSE: sequence operator precedence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Table 16-1: "or" is below "##", "or" is below "and", "intersect" is below "##", "throughout" is below "##".
// Each trace differs under the wrong parse: 10010110 would be (a or b) ##1 c, and so on.
// CHECK: P1=10010110 P2=00110100 P3=00001000 P4=00001000

module top;
  bit clk, a, b, c, d, e; int t;
  bit [0:7] A = 8'b10010010, B = 8'b00001001, C = 8'b00110100, D = 8'b00001000, E = 8'b00011010;
  bit [0:7][3:0] P1, P2, P3, P4;
  cover property (@(posedge clk) a or b ##1 c) P1[t]++;
  cover property (@(posedge clk) a and b or c) P2[t]++;
  cover property (@(posedge clk) a ##1 b intersect c ##1 d) P3[t]++;
  cover property (@(posedge clk) e throughout a ##1 b) P4[t]++;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t]; c = C[t]; d = D[t]; e = E[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P1=%h P2=%h P3=%h P4=%h", P1, P2, P3, P4);
  end
endmodule
