// CLAUSE: mixed time scope error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module child; endmodule
module top;
timeunit 1ns/1ps; child d();
initial begin

$display("PASS"); $finish;
end
endmodule
