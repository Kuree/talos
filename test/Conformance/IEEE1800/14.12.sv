// CLAUSE: cycle literal default
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
default clocking cb @(posedge clk); endclocking
initial begin
##2; if($time!=15) $fatal(1,"two cycles t=%0t",$time);
$display("PASS"); $finish;
end
initial begin #60; $fatal(1,"clocking watchdog"); end
endmodule
