// CLAUSE: single module clockvar strobe
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: LOCAL_SAMPLE=7

module top;timeunit 1ns;timeprecision 1ns;
bit clk;int data;clocking cb @(posedge clk);input #0 data;endclocking
initial begin
#1;data=7;clk=1;#1;$strobe("LOCAL_SAMPLE=%0d",cb.data);#1;
$display("PASS");$finish;end

endmodule
