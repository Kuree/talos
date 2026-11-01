// CLAUSE: strong sequence fails on an insufficient finite word
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %not %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]|[fF][aA][tT][aA][lL]}}

module top;bit c=0;always #1 c=~c;a:assert property(@(posedge c)strong(1 ##1 1))else $fatal(1,"strong end");initial #2 $finish;endmodule
