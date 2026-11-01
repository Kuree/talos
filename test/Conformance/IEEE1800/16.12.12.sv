// CLAUSE: until
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// s@0: q arrives at tick 3 with p false there, which only the _with forms reject. s@5: p falls at tick 6 before
// q. s@9: q never arrives, so the strong forms fail at the end and the weak forms do not.
// CHECK: U=000000100000 S=000000100000 UW=000100100000 SW=000100100000
// CHECK-DAG: s_until failed at end
// CHECK-DAG: s_until_with failed at end

module top;
  bit clk, s, p, q; int t;
  bit [0:11] SS = 12'b100001000100, PP = 12'b111001000111, Q = 12'b000100010000;
  bit [0:11][3:0] U, S, UW, SW;
  assert property (@(posedge clk) s |-> p until q) else if (t < 12) U[t]++; else $fatal(1, "until at end");
  assert property (@(posedge clk) s |-> p s_until q) else if (t < 12) S[t]++; else $display("s_until failed at end");
  assert property (@(posedge clk) s |-> p until_with q) else if (t < 12) UW[t]++; else $fatal(1, "until_with at end");
  assert property (@(posedge clk) s |-> p s_until_with q) else if (t < 12) SW[t]++; else $display("s_until_with failed at end");
  initial begin
    for (t = 0; t < 12; t++) begin
      s = SS[t]; p = PP[t]; q = Q[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("U=%h S=%h UW=%h SW=%h", U, S, UW, SW);
  end
endmodule
