// CLAUSE: strength wins pull
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
wire y; logic a=0,en=1; pullup(y); bufif1(strong1,strong0) g(y,a,en);
initial begin
#1; if(y!==0) $fatal; en=0; #1; if(y!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
