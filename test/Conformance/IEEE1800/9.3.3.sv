// CLAUSE: sequential relative delays
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

int value=0;
initial begin #1; value=1; #2; value=2; if($time!=3) $fatal; $display("PASS"); $finish; end

endmodule
