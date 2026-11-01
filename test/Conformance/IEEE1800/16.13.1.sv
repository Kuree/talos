// CLAUSE: multiclock sequence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit a,b;int hits;
sequence s;@(posedge a)1 ##1 @(posedge b)1;endsequence
a1:assert property(s)hits++;else $fatal;
initial begin #1;a=1;#1;b=1;#1;if(hits!=1)$fatal;$display("PASS");$finish;end endmodule
