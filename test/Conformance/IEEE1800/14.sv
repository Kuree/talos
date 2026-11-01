// CLAUSE: Clocking
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
  bit clk=0; int data;
  clocking cb @(posedge clk); output data; endclocking
  initial cb.data=3;
endmodule
