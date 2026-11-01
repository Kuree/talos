// CLAUSE: nonprocedural deferred
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: DEFERRED

module top;int value=1;
a:assert final(value>0)$display("DEFERRED");else $fatal;
initial begin #1;value=2;#1;$display("PASS");$finish;end endmodule
