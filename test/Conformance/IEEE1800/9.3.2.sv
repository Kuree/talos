// CLAUSE: fork capture and wait
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top; task automatic t(); fork return; join_none endtask initial t(); endmodule
