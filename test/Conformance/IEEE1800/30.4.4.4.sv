// CLAUSE: ifnone conditional pair control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,c,output wire y); timeunit 1ns; timeprecision 1ns; assign y=a; specify if(c) (a=>y)=2; ifnone (a=>y)=3; endspecify endmodule
module top;
timeunit 1ns; timeprecision 1ns;
logic a=0,c=0; wire y; cell_t u(a,c,y);
initial begin
c=1; #5; a=1; #1; if(y!==0) $fatal; #2; if(y!==1) $fatal; c=0; a=0; #4; if(y!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
