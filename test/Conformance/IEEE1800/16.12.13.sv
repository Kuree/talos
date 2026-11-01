// CLAUSE: eventually
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Attempts s@0,4,7 complete at ticks 3, 8, 8 under s_eventually (each s=0 tick adds one vacuous pass). The ranged
// forms give up after [1:2]. The attempt on the last tick is false only for the strong forms.
// CHECK: SP=01120110310 W=00100010000 R=00100010000
// CHECK-DAG: s_eventually failed at end
// CHECK-DAG: s_eventually[1:2] failed at end

module top;
  bit clk, s, b; int t;
  bit [0:10] SS = 11'b10001001001, B = 11'b00010000100;
  bit [0:10][3:0] SP, W, R;
  assert property (@(posedge clk) s |-> s_eventually b) SP[t]++;
    else if (t < 11) $fatal(1, "s_eventually failed early"); else $display("s_eventually failed at end");
  assert property (@(posedge clk) s |-> eventually [1:2] b) else if (t < 11) W[t]++; else $fatal(1, "weak at end");
  assert property (@(posedge clk) s |-> s_eventually [1:2] b) else if (t < 11) R[t]++; else $display("s_eventually[1:2] failed at end");
  initial begin
    for (t = 0; t < 11; t++) begin
      s = SS[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("SP=%h W=%h R=%h", SP, W, R);
  end
endmodule
