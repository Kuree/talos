// CLAUSE: clock flow
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk;int hits;
sequence s;1 ##1 1;endsequence
property p;@(posedge clk)s;endproperty
a:assert property(p)hits++;else $fatal;
initial begin repeat(3)begin #1;clk=1;#1;clk=0;end if(hits==0)$fatal;$display("PASS");$finish;end endmodule
