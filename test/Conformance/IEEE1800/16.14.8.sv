// CLAUSE: nonvacuous control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit clk,antecedent=0;int hits;
a:assert property(@(posedge clk)antecedent |-> 1)hits++;else $fatal;
initial begin $assertvacuousoff(0);#1;clk=1;#1;if(hits!=0)$fatal;$display("PASS");$finish;end endmodule
