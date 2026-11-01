// CLAUSE: An empty module instance provides a structural elaboration control for the empty checker i
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module c; endmodule module top; c inst(); initial begin $display("PASS");$finish;end endmodule
