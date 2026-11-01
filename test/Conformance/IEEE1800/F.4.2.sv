// CLAUSE: checker rewriting preserves a failing assertion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

checker C(input bit clk);a:assert property(@(posedge clk)0)else $fatal(1,"checker executed");endchecker
module top;bit c=0;always #1 c=~c;C check(c);initial #4 $finish;endmodule
