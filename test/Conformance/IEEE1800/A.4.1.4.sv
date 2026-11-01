// CLAUSE: Checker instance connects its actual arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

checker C(input bit clk,input bit d);a:assert property(@(posedge clk)d)$display("PASS");endchecker
module top;bit clk=0;
C c(clk,1'b1);
initial begin #1;clk=1;#1;$finish;end
endmodule
