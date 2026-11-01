// CLAUSE: consecutive repeat
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One real sample of the chapter: a[*2] ##1 b matches when two consecutive a are followed by b.
// CHECK: M=0010011

module top;
  bit clk, a, b; int t;
  bit [0:6] A = 7'b1101110, B = 7'b0010011;
  bit [0:6][3:0] M;
  cover property (@(posedge clk) a[*2] ##1 b) M[t]++;
  initial begin
    for (t = 0; t < 7; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("M=%h", M);
  end
endmodule
