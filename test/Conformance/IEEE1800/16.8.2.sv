// CLAUSE: sequence local output
// XFAIL: *
// The bounded monitor cannot execute this local-output sequence formal.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk,one=1,zero,reset;int passes,failures;

sequence s(local output int v);(one,v=3);endsequence
property p;int saved;s(saved) ##1 saved==3;endproperty
a:assert property(@(posedge clk) disable iff(reset) p) passes++;else failures++;
initial begin repeat(6)begin #1;clk=1;#1;clk=0;end reset=1;#1;
if(passes==0 || failures!=0)$fatal(1,"assertion result");$display("PASS");$finish;end endmodule
