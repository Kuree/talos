// CLAUSE: pathpulse allows short pulse
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --timescale=1ns/1ps -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire a,c,output wire y); timeunit 1ns; timeprecision 1ps; assign y=a; specify specparam PATHPULSE$=(0,0); (a=>y)=4; endspecify endmodule
module top;
timeunit 1ns; timeprecision 1ps;
logic a=0,c=0; wire y; cell_t u(a,c,y);
initial begin
#6; a=1; #1; a=0; #3.5; if(y!==1) $fatal(1,"PATHPULSE short pulse not passed: y=%b",y); #1; if(y!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
