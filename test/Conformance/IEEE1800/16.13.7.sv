// CLAUSE: local initial assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk;int hits;
sequence s;int v=3;@(posedge clk)v==3;endsequence
a:assert property(s)hits++;else $fatal;
initial begin #1;clk=1;#1;if(hits!=1)$fatal;$display("PASS");$finish;end endmodule
