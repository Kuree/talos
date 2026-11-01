// CLAUSE: Derived unbounded temporal operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Failure ticks for attempts s@0,5,9 (p 111001000111, q 000100010000). always/until fail at 3 and 6; p holds from 9 so weak forms pass there; s_eventually/s_until fail only at the end for attempt 9; until_with needs p on the q tick (fails at 3, 6); only strong forms fail at the end.
// CHECK-DAG: {{^s_eventually at end$}}
// CHECK-DAG: {{^s_until at end$}}
// CHECK-DAG: {{^s_until_with at end$}}
// CHECK-DAG: {{^expanded s_until_with at end$}}
// CHECK-DAG: A=000100100000 AE=000100100000 EV=000000000000
// CHECK-DAG: SU=000000100000 UW=000100100000 UWE=000100100000 SW=000100100000 SWE=000100100000

module top;
  bit clk, s, p, q; int t;
  bit [0:11] S = 12'b100001000100, PP = 12'b111001000111, Q = 12'b000100010000;
  bit [0:11][3:0] A, AE, EV, SU, UW, UWE, SW, SWE;
  assert property (@(posedge clk) s |-> always p) else if (t < 12) A[t]++; else $fatal(1, "always at end");
  assert property (@(posedge clk) s |-> p until 1'b0) else if (t < 12) AE[t]++; else $fatal(1, "until 0 at end");
  assert property (@(posedge clk) s |-> s_eventually q) else if (t < 12) EV[t]++; else $display("s_eventually at end");
  assert property (@(posedge clk) s |-> p s_until q) else if (t < 12) SU[t]++; else $display("s_until at end");
  assert property (@(posedge clk) s |-> p until_with q) else if (t < 12) UW[t]++; else $fatal(1, "until_with at end");
  assert property (@(posedge clk) s |-> p until (p && q)) else if (t < 12) UWE[t]++; else $fatal(1, "expanded until_with at end");
  assert property (@(posedge clk) s |-> p s_until_with q) else if (t < 12) SW[t]++; else $display("s_until_with at end");
  assert property (@(posedge clk) s |-> p s_until (p && q)) else if (t < 12) SWE[t]++; else $display("expanded s_until_with at end");
  initial begin
    for (t = 0; t < 12; t++) begin
      s = S[t]; p = PP[t]; q = Q[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("A=%h AE=%h EV=%h", A, AE, EV);
    $display("SU=%h UW=%h UWE=%h SW=%h SWE=%h", SU, UW, UWE, SW, SWE);
  end
endmodule
