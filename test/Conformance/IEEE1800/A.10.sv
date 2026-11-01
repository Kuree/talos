// CLAUSE: Reject automatic storage at module scope
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// CHECK: error: automatic variables can only be declared in procedural contexts

module top;automatic int n;endmodule
