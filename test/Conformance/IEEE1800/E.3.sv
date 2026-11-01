// CLAUSE: reject default charge strength above 250
// XFAIL: *
// The optional directive does not produce the required observed default/range behavior.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

`default_trireg_strength 251
module top;endmodule
