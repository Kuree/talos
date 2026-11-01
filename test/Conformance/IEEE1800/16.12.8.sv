// CLAUSE: property iff
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk,one=1,zero,reset;int passes,failures;


a:assert property(@(posedge clk) disable iff(reset) one iff one) passes++;else failures++;
initial begin repeat(6)begin #1;clk=1;#1;clk=0;end reset=1;#1;
if(passes==0 || failures!=0)$fatal(1,"assertion result");$display("PASS");$finish;end endmodule
