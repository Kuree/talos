// CLAUSE: invalid dynamic part width
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top; int w=2; logic [7:0] a,b; initial b=a[0+:w]; endmodule
