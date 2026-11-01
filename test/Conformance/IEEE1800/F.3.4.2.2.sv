// CLAUSE: Derived delay and concatenation operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Each derived delay and its expansion report every endpoint per tick. a is at ticks 0 and 3, b at 2 3 4 7.
// CHECK: D1=00101000 E1=00101000
// CHECK: D2=00111001 E2=00111001
// CHECK: D3=00011000 E3=00011000
// CHECK: D4=00112002 E4=00112002
// CHECK: PLUS=00112002 STAR=00122002

module top;
  bit clk, a, b; int t;
  bit [0:7] A = 8'b10010000, B = 8'b00111001;
  bit [0:7][3:0] D1, E1, D2, E2, D3, E3, D4, E4, PLUS, STAR;
  cover sequence (@(posedge clk) a ##[1:2] b) D1[t]++;
  cover sequence (@(posedge clk) a ##1 1[*0:1] ##1 b) E1[t]++;
  cover sequence (@(posedge clk) ##2 b) D2[t]++;
  cover sequence (@(posedge clk) 1[*2] ##1 b) E2[t]++;
  cover sequence (@(posedge clk) a ##[0:1] b) D3[t]++;
  cover sequence (@(posedge clk) (a ##0 b) or (a ##1 b)) E3[t]++;
  cover sequence (@(posedge clk) a ##[1:$] b) D4[t]++;
  cover sequence (@(posedge clk) a ##1 1[*0:$] ##1 b) E4[t]++;
  cover sequence (@(posedge clk) a ##[+] b) PLUS[t]++;
  cover sequence (@(posedge clk) a ##[*] b) STAR[t]++;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("D1=%h E1=%h", D1, E1);
    $display("D2=%h E2=%h", D2, E2);
    $display("D3=%h E3=%h", D3, E3);
    $display("D4=%h E4=%h", D4, E4);
    $display("PLUS=%h STAR=%h", PLUS, STAR);
  end
endmodule
