// CLAUSE: tri alias named control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
bit a=1; clocking cb @(posedge clk); input #0 copy=a; endclocking
initial begin
@(cb); if(cb.copy!=1) $fatal;
$display("PASS"); $finish;
end
initial begin #40; $fatal(1,"clocking watchdog"); end
endmodule
