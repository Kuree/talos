// CLAUSE: strong sequence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Fails: the attempts at ticks 1 to 3 see a bad state. Holds strongly: strong(s) completed at tick 1. Holds:
// "always" with no bad state stays silent. Pending: s_eventually has an unmet obligation and is never a pass.
// CHECK: SP=0100 F=0021
// CHECK-NOT: pending
// CHECK: pending obligation unmet at end
// CHECK-NOT: pending

module top;
  bit clk, a, b, never; int t;
  bit [0:3] A = 4'b1100, B = 4'b0100;
  bit [0:3][3:0] SP, F;
  assert property (@(posedge clk) strong(a ##1 b)) SP[t]++; else F[t]++;
  assert property (@(posedge clk) always 1'b1) else $fatal(1, "holds, not strongly: reported as failed");
  assert property (@(posedge clk) t == 0 |-> s_eventually never)
    if (t == 0) $fatal(1, "pending attempt passed"); else;
    else if (t < 4) $fatal(1, "pending attempt failed early"); else $display("pending obligation unmet at end");
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("SP=%h F=%h", SP, F);
  end
endmodule
