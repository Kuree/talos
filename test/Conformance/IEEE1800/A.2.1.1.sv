// CLAUSE: Typed parameter with a default value
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top #(parameter int N=7);initial begin if(N!=7)$fatal;$display("PASS");end endmodule
