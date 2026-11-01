// CLAUSE: time scale retrieval
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

timeunit 100ps; timeprecision 10ps;
module child; timeunit 10ns; timeprecision 1ns; endmodule
module top;
timeunit 1ns; timeprecision 1ps;
child c();
initial begin
 if($timeunit!=-9 || $timeprecision!=-12 || $timeunit(c)!=-8 || $timeprecision(c)!=-9 || $timeunit($unit)!=-10 || $timeprecision($unit)!=-11 || $timeunit($root)!=-12 || $timeprecision($root)!=-12) $fatal;
 $display("PASS"); $finish;
end
endmodule
