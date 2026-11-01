// CLAUSE: interconnect wire control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module source(output wire value); assign value=1'b1; endmodule
module top; wire n; source d(n); endmodule
