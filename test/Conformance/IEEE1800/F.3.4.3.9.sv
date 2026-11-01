// CLAUSE: Derived bounded temporal operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Failure ticks for attempts s@0,3,6,9,12 with b = 0 1 0 0 1 1 1 0 1 1 0 0 1: nexttime[0] fails at 0,3; nexttime[2] at 2,11; always[1:2] at 2,7,10; eventually[1:2] at 11; each beside its nexttime expansion. The strong forms alone also fail at the end, for the attempt on the last tick.
// CHECK-DAG: {{^s_eventually at end$}}
// CHECK-DAG: {{^s_always at end$}}
// CHECK-DAG: {{^s_nexttime at end$}}
// CHECK-DAG: N0=1001000000000 N2=0010000000010
// CHECK-DAG: AL=0010000100100 ALE=0010000100100
// CHECK-DAG: EV=0000000000010 EVE=0000000000010
// CHECK-DAG: SEV=0000000000010 SAL=0010000100100 SN=0010000000010

module top;
  bit clk, s, b; int t;
  bit [0:12] S = 13'b1001001001001, B = 13'b0100111011001;
  bit [0:12][3:0] N0, N2, AL, ALE, EV, EVE, SEV, SAL, SN;
  assert property (@(posedge clk) s |-> nexttime[0] b) else if (t < 13) N0[t]++;
  assert property (@(posedge clk) s |-> nexttime[2] b) else if (t < 13) N2[t]++; else $fatal(1, "nexttime at end");
  assert property (@(posedge clk) s |-> always [1:2] b) else if (t < 13) AL[t]++; else $fatal(1, "always at end");
  assert property (@(posedge clk) s |-> (nexttime[1] b) and (nexttime[2] b)) else if (t < 13) ALE[t]++; else $fatal(1, "expanded always at end");
  assert property (@(posedge clk) s |-> eventually [1:2] b) else if (t < 13) EV[t]++; else $fatal(1, "eventually at end");
  assert property (@(posedge clk) s |-> (nexttime[1] b) or (nexttime[2] b)) else if (t < 13) EVE[t]++; else $fatal(1, "expanded eventually at end");
  assert property (@(posedge clk) s |-> s_eventually [1:2] b) else if (t < 13) SEV[t]++; else $display("s_eventually at end");
  assert property (@(posedge clk) s |-> s_always [1:2] b) else if (t < 13) SAL[t]++; else $display("s_always at end");
  assert property (@(posedge clk) s |-> s_nexttime[2] b) else if (t < 13) SN[t]++; else $display("s_nexttime at end");
  initial begin
    for (t = 0; t < 13; t++) begin
      s = S[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("N0=%h N2=%h", N0, N2);
    $display("AL=%h ALE=%h", AL, ALE);
    $display("EV=%h EVE=%h", EV, EVE);
    $display("SEV=%h SAL=%h SN=%h", SEV, SAL, SN);
  end
endmodule
