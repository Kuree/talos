// CLAUSE: input multiple blocks skews
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
int value=0; clocking early @(posedge clk); input #1step value; endclocking clocking late @(posedge clk); input #0 value; endclocking always @(posedge clk) value<=7;
initial begin
@(early); #1; if(early.value!=0 || late.value!=7) $fatal;
$display("PASS"); $finish;
end
initial begin #60; $fatal(1,"clocking watchdog"); end
endmodule
