// CLAUSE: range query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.6.3: $isunbounded is true only for a parameter whose value is $.
// CHECK: i=1 j=0

module top;
  parameter int i = $, j = 3;
  initial $display("i=%b j=%b", $isunbounded(i), $isunbounded(j));
endmodule
