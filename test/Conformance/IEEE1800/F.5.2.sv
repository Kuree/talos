// CLAUSE: Tight satisfaction without local variables finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Tight satisfaction fixes where a match ends: ##1 concatenates, ##0 overlaps one letter, "or" unions, intersect
// needs equal words, first_match keeps the shortest, and R[*1:$] splits the word. Every endpoint is reported.
// a is at ticks 1 2 3, b at 2 3 4, c at 3.
// CHECK: CAT=000100 FUSE=001100 OR=001210 ISECT=000100 FM=002100 PLUS=012300

module top;
  bit clk, a, b, c; int t;
  bit [0:5] A = 6'b011100, B = 6'b001110, C = 6'b000100;
  bit [0:5][3:0] CAT, FUSE, OR, ISECT, FM, PLUS;
  cover sequence (@(posedge clk) a ##1 c) CAT[t]++;
  cover sequence (@(posedge clk) a ##0 b) FUSE[t]++;
  cover sequence (@(posedge clk) (a ##1 b) or (a ##2 c)) OR[t]++;
  cover sequence (@(posedge clk) (a ##1 b) intersect (a ##[1:2] c)) ISECT[t]++;
  cover sequence (@(posedge clk) first_match(a ##[0:2] b)) FM[t]++;
  cover sequence (@(posedge clk) a[*1:$]) PLUS[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("CAT=%h FUSE=%h OR=%h ISECT=%h FM=%h PLUS=%h", CAT, FUSE, OR, ISECT, FM, PLUS);
  end
endmodule
