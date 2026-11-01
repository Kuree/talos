// CLAUSE: bounded temporal property example
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk,one=1;int hits;
a:assert property(@(posedge clk)one[*2] |-> (one ##[1:2]one))hits++;else $fatal;
initial begin repeat(5)begin #1;clk=1;#1;clk=0;end if(hits==0)$fatal;$display("PASS");$finish;end endmodule
