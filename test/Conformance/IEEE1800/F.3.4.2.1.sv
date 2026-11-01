// CLAUSE: Derived consecutive repetition operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Each derived form and its expansion report every endpoint per tick. b is 1 1 1 0 1 0 0 1 1 0.
// CHECK: D2=0110000010 E2=0110000010
// CHECK: D12=1220100120 E12=1220100120
// CHECK: PLUS=1230100120 ONE=1230100120
// CHECK: STAR=0004001003 ZERO=0004001003

module top;
  bit clk, b, c; int t;
  bit [0:9] B = 10'b1110100110, C = 10'b0001001001;
  bit [0:9][3:0] D2, E2, D12, E12, PLUS, ONE, STAR, ZERO;
  cover sequence (@(posedge clk) b[*2]) D2[t]++;
  cover sequence (@(posedge clk) b ##1 b) E2[t]++;
  cover sequence (@(posedge clk) b[*1:2]) D12[t]++;
  cover sequence (@(posedge clk) b or (b ##1 b)) E12[t]++;
  cover sequence (@(posedge clk) b[+]) PLUS[t]++;
  cover sequence (@(posedge clk) b[*1:$]) ONE[t]++;
  cover sequence (@(posedge clk) b[*] ##1 c) STAR[t]++;
  cover sequence (@(posedge clk) b[*0:$] ##1 c) ZERO[t]++;
  initial begin
    for (t = 0; t < 10; t++) begin
      b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("D2=%h E2=%h", D2, E2);
    $display("D12=%h E12=%h", D12, E12);
    $display("PLUS=%h ONE=%h", PLUS, ONE);
    $display("STAR=%h ZERO=%h", STAR, ZERO);
  end
endmodule
