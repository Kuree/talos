// CLAUSE: Assertion item in a checker body
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

checker C(input bit clk);a:assert property(@(posedge clk)1)$display("PASS");endchecker
module top;bit clk=0;
C c(clk);
initial begin #1;clk=1;#1;$finish;end
endmodule
