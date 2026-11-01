// CLAUSE: consecutive repeat
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// b@1,3 then c@5: only [=2] tolerates the gap. b@8,9 then c@10: all three match, each at its own tick.
// CHECK: REP=000000000100 GOTO=000000000010 NONC=000001000010

module top;
  bit clk, s, b, c; int t;
  bit [0:11] S = 12'b100000010000, B = 12'b010100001100, C = 12'b000001000010;
  bit [0:11][3:0] REP, GOTO, NONC;
  cover property (@(posedge clk) s ##1 b[*2]) REP[t]++;
  cover property (@(posedge clk) s ##1 b[->2] ##1 c) GOTO[t]++;
  cover property (@(posedge clk) s ##1 b[=2] ##1 c) NONC[t]++;
  initial begin
    for (t = 0; t < 12; t++) begin
      s = S[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("REP=%h GOTO=%h NONC=%h", REP, GOTO, NONC);
  end
endmodule
