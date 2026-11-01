// CLAUSE: time query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 1ps;time t;initial begin #2;t=$time;if(t!=2)$fatal;$display("PASS");$finish;end endmodule
