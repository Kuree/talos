// CLAUSE: assume-constrained free checker variable is assigned at each clock
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: SAMPLE
// CHECK-DAG: {{^PASS$}}

checker C(input bit clk);
rand bit v;
a:assume property(@(posedge clk)v==1);
b:assert property(@(posedge clk)v)$display("SAMPLE");else $fatal(1,"free variable");
endchecker
module top;bit c=0;always #1 c=~c;C check(c);
initial begin #5;$display("PASS");$finish;end endmodule
