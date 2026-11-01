// CLAUSE: sequence triggered
// XFAIL: *
// The sequence method matched is not lowered: "unsupported system call matched".
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// e1 ends at clk ticks 1 and 4. matched holds that result for the next slow tick, which r ##1 reads at periods 3
// and 6, and a slow tick with no match in between (period 7) sees false. triggered needs the ending clock.
// CHECK: M=00010010 T=01001000

module top;
  bit clk, slow, r, x, y; int t;
  bit [0:7] X = 8'b10010000, Y = 8'b01001000, SLOW = 8'b01011011, R = 8'b01001010;
  bit [0:7] M, T;
  sequence e1(a, b); @(posedge clk) a ##1 b; endsequence
  cover property (@(posedge slow) r ##1 e1(x, y).matched) M[t] = 1;
  cover property (@(posedge slow) r ##1 @(posedge clk) e1(x, y).triggered) T[t] = 1;
  initial begin
    for (t = 0; t < 8; t++) begin
      x = X[t]; y = Y[t]; r = R[t];
      #1 slow = SLOW[t];
      #1 slow = 0; clk = 1;
      #1 clk = 0;
      #1;
    end
    $display("M=%b T=%b", M, T);
  end
endmodule
