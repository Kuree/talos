// CLAUSE: within
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// a ##1 b lies inside c ##3 d at ticks 0-3 and 5-8 (ending together). It runs past the end at 10-13 and starts
// before the start at 16-19, so only the outer sequence matches there.
// CHECK: W=00010000100000000000 OUTER=00010000100001000001

module top;
  bit clk, a, b, c, d; int t;
  bit [0:19] A = 20'b01000001000001010000, B = 20'b00100000100000101000;
  bit [0:19] C = 20'b10000100001000001000, D = 20'b00010000100001000001;
  bit [0:19][3:0] W, OUTER;
  cover property (@(posedge clk) (a ##1 b) within (c ##3 d)) W[t]++;
  cover property (@(posedge clk) c ##3 d) OUTER[t]++;
  initial begin
    for (t = 0; t < 20; t++) begin
      a = A[t]; b = B[t]; c = C[t]; d = D[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("W=%h OUTER=%h", W, OUTER);
  end
endmodule
