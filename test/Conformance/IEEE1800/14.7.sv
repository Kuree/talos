// CLAUSE: virtual interface clocking read
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I(input bit clk); timeunit 1ns; timeprecision 1ns; int value=7; clocking cb @(posedge clk); input #0 value; endclocking endinterface
module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
I bus(clk); virtual I vi;
initial begin
vi=bus; @(vi.cb); if(vi.cb.value!=7) $fatal;
$display("PASS"); $finish;
end
initial begin #60; $fatal(1,"clocking watchdog"); end
endmodule
