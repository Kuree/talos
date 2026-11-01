// CLAUSE: first match
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Attempt 0 has three matches of a ##[1:3] b. first_match keeps only the earliest of them.
// CHECK: PLAIN=01110010 FM=01000010

module top;
  bit clk, a, b; int t;
  bit [0:7] A = 8'b10001000, B = 8'b01110010;
  bit [0:7][3:0] PLAIN, FM;
  cover sequence (@(posedge clk) a ##[1:3] b) PLAIN[t]++;
  cover sequence (@(posedge clk) first_match(a ##[1:3] b)) FM[t]++;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("PLAIN=%h FM=%h", PLAIN, FM);
  end
endmodule
