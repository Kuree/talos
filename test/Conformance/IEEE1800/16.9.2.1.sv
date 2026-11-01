// CLAUSE: empty repeat concat
// XFAIL: *
// The rule that (empty ##0 seq) never matches is rejected as "##0 empty fusion", not executed.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// (empty ##1 y) is (##0 y), so E1 hits at each y while E2, with x[*1], needs x a tick before.
// b ##1 a[*0:1] ##2 c equals (b ##2 c) or (b ##1 a ##2 c). (empty ##0 y) never matches, so E5 follows c alone.
// CHECK: E1=01010000000000000 E2=01000000000000000
// CHECK: E3=00000010000100000 E4=00000010000100000
// CHECK: E5=00000010000100001

module top;
  bit clk, x, y, a, b, c; int t;
  bit [0:16] X = 17'b10000000000000000, Y = 17'b01010000000000000;
  bit [0:16] B = 17'b00001000100001000, A = 17'b00000000010000000, C = 17'b00000010000100001;
  bit [0:16][3:0] E1, E2, E3, E4, E5;
  cover property (@(posedge clk) x[*0] ##1 y) E1[t]++;
  cover property (@(posedge clk) x[*1] ##1 y) E2[t]++;
  cover property (@(posedge clk) b ##1 a[*0:1] ##2 c) E3[t]++;
  cover property (@(posedge clk) (b ##2 c) or (b ##1 a ##2 c)) E4[t]++;
  cover property (@(posedge clk) (x[*0] ##0 y) or c) E5[t]++;
  initial begin
    for (t = 0; t < 17; t++) begin
      x = X[t]; y = Y[t]; a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("E1=%h E2=%h", E1, E2);
    $display("E3=%h E4=%h", E3, E4);
    $display("E5=%h", E5);
  end
endmodule
