// CLAUSE: tri same value drives control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
bit value=0; clocking cb @(posedge clk); output value; endclocking
initial begin
@(cb); cb.value<=1; cb.value<=1; #1; if(value!=1) $fatal;
$display("PASS"); $finish;
end
initial begin #40; $fatal(1,"clocking watchdog"); end
endmodule
