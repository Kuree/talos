// CLAUSE: invalid timed constructor
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

class A; function new(); #1; endfunction endclass
module top; A a; initial a=new; endmodule
