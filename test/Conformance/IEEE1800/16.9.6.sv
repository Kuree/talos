// CLAUSE: sequence intersect
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Operands of intersect shall start and end together. At attempt 4 the operands end at ticks 6 and 5: "and"
// matches at the later one, intersect has no match.
// CHECK: I1=00100000 I2=01000000 A2=01000010

module top;
  bit clk, a, b, c, d; int t;
  bit [0:7] S = 8'b10001000, B = 8'b01100010, D = 8'b01100100;
  bit [0:7][3:0] I1, I2, A2;
  cover property (@(posedge clk) (a ##[1:2] b) intersect (c ##2 d)) I1[t]++;
  cover property (@(posedge clk) (a ##[1:2] b) intersect (c ##[1:2] d)) I2[t]++;
  cover property (@(posedge clk) (a ##[1:2] b) and (c ##[1:2] d)) A2[t]++;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = S[t]; c = S[t]; b = B[t]; d = D[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("I1=%h I2=%h A2=%h", I1, I2, A2);
  end
endmodule
