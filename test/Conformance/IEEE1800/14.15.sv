// CLAUSE: synchronous input event
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0; always #5 clk=~clk;
bit value=0; clocking cb @(posedge clk); input #0 value; endclocking initial begin #6; value=1; end
initial begin
@(posedge cb.value); if($time!=15 || cb.value!=1) $fatal(1,"sample event t=%0t",$time);
$display("PASS"); $finish;
end
initial begin #60; $fatal(1,"clocking watchdog"); end
endmodule
