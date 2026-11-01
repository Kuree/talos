// CLAUSE: printtimescale
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: 1ns
// CHECK-DAG: 1ps

module top;timeunit 1ns;timeprecision 1ps;initial begin $printtimescale(top);$display("PASS");$finish;end endmodule
