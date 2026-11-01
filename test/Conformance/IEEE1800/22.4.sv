// CLAUSE: nested include
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -I%S/Inputs/22.4 -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`include "one.svh"
module top; initial begin if(`NESTED!=7) $fatal; $display("PASS"); $finish; end endmodule
