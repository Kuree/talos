// CLAUSE: rounding and scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;timeunit 1ns;timeprecision 100ps;int value;real start;
initial begin start=$realtime;value<=1;#0.04;
if(value!=0 || $realtime!=start)$fatal(1,"rounded zero");#1step;
if(value!=1 || $realtime<0.099999 || $realtime>0.100001)$fatal(1,"step=%0f",$realtime);
$display("PASS");$finish;end endmodule
