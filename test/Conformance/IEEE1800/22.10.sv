// CLAUSE: celldefine directive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`celldefine
module leaf;endmodule
`endcelldefine
module top;leaf l();initial begin $display("PASS");$finish;end endmodule
