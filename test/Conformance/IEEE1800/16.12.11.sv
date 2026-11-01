// CLAUSE: bounded always
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Failure ticks for attempts s@0,4,8. b is false at 2 outside [0:1], at 5, and at 8 outside [1:2]. The attempt at
// the last tick has not seen its whole range: weak forms stay silent, s_always is false as a tick does not exist.
// CHECK: A=0000010010000 U=0010010010000 W=0010010000000 S=0000010010000
// CHECK-NOT: s_always
// CHECK: s_always failed at end
// CHECK-NOT: s_always

module top;
  bit clk, s, b; int t;
  bit [0:12] SS = 13'b1000100010001, B = 13'b1100100001101;
  bit [0:12][3:0] A, U, W, S;
  assert property (@(posedge clk) s |-> always [0:1] b) else if (t < 13) A[t]++; else $fatal(1, "always[0:1] at end");
  assert property (@(posedge clk) s |-> always b) else if (t < 13) U[t]++; else $fatal(1, "always at end");
  assert property (@(posedge clk) s |-> always [1:2] b) else if (t < 13) W[t]++; else $fatal(1, "always[1:2] at end");
  assert property (@(posedge clk) s |-> s_always [0:1] b) else if (t < 13) S[t]++; else $display("s_always failed at end");
  initial begin
    for (t = 0; t < 13; t++) begin
      s = SS[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("A=%h U=%h W=%h S=%h", A, U, W, S);
  end
endmodule
