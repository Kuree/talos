// CLAUSE: typed sequence argument
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One count per tick: ##0 fuses, ##N is N ticks later, ##[1:2] reaches tick 4 from both a@2 and a@3.
// CHECK: C0=001000 C1=000010 C2=001010 CR=001020

module top;
  bit clk, a, b; int t;
  bit [0:5] A = 6'b101100, B = 6'b001010;
  bit [0:5][3:0] C0, C1, C2, CR;
  cover property (@(posedge clk) a ##0 b) C0[t]++;
  cover property (@(posedge clk) a ##1 b) C1[t]++;
  cover property (@(posedge clk) a ##2 b) C2[t]++;
  cover property (@(posedge clk) a ##[1:2] b) CR[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("C0=%h C1=%h C2=%h CR=%h", C0, C1, C2, CR);
  end
endmodule
