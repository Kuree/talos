// CLAUSE: Neutral property satisfaction combines Boolean operands
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;bit clk,a=1,b=0;int n;
assert property(@(posedge clk)(a and not b))n++;else $fatal(1,"neutral satisfaction");
initial begin #1;clk=1;#1;if(n!=1)$fatal(1,"assertion attempt");$display("PASS");$finish;end endmodule
