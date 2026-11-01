// CLAUSE: write input error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
int value; clocking cb @(posedge clk); input value; endclocking
initial begin
cb.value<=7;
$display("PASS"); $finish;
end
initial begin #60; $fatal(1,"clocking watchdog"); end
endmodule
