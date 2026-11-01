// CLAUSE: throughout
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// c drops mid-sequence for attempt 4 and on the final tick for attempt 12, which kills the match though the
// plain sequence still matches at ticks 6 and 14.
// CHECK: T=0010000000000000 PLAIN=0010001000000010

module top;
  bit clk, a, b, c; int t;
  bit [0:15] A = 16'b1000100010001000, B = 16'b0010001000000010, C = 16'b1110101011101100;
  bit [0:15][3:0] T, PLAIN;
  cover property (@(posedge clk) c throughout (a ##2 b)) T[t]++;
  cover property (@(posedge clk) a ##2 b) PLAIN[t]++;
  initial begin
    for (t = 0; t < 16; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("T=%h PLAIN=%h", T, PLAIN);
  end
endmodule
