// CLAUSE: udp level dominance
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

primitive p(q,clk,set);
output q;reg q;input clk,set;initial q=0;
table
? 1 : ? : 1;
r ? : ? : 0;
f 0 : ? : -;
? (10) : ? : -;
endtable endprimitive
module top;logic clk=0,set=0;wire q;p d(q,clk,set);
initial begin #1;set=1;clk=1;#1;if(q!==1)$fatal;$display("PASS");$finish;end endmodule
