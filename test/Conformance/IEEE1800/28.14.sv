// CLAUSE: rtran strength reduction
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: B_STRENGTH=Pu1

module top;
timeunit 1ns; timeprecision 1ns;
wire a,b; supply1 strong_source; assign a=strong_source; rtran g(a,b);
initial begin
#1; if(a!==1 || b!==1) $fatal; $display("B_STRENGTH=%v",b);
$display("PASS"); $finish;
end
endmodule
