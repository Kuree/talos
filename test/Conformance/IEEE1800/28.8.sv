// CLAUSE: tranif bidirectional
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
wire a,b; logic drive=1,en=0; assign a=drive; tranif1 g(a,b,en);
initial begin
#1; if(b!==1'bz) $fatal; en=1; #1; if(b!==1) $fatal; drive=0; #1; if(b!==0) $fatal; en=0; #1; if(b!==1'bz) $fatal;
$display("PASS"); $finish;
end
endmodule
