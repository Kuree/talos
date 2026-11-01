// CLAUSE: concurrent nested and variant
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 1ns;
bit clk=0;always #1 clk=~clk;
int hits=0;p:assert property(@(posedge clk)(1'b1 |=> 1'b1) and 1'b1)hits++;else $fatal(1,"nested and");
initial begin
#6;if(hits!=2)$fatal(1,"nested and hits=%0d",hits);
$display("PASS");$finish;end
initial begin #20;$fatal(1,"watchdog");end endmodule
