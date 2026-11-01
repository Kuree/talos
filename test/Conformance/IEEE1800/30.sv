// CLAUSE: Specify paths
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module cell_t(input wire [1:0] a,input wire c,output wire y); timeunit 1ns; timeprecision 1ns; assign y=&a; specify (a*>y)=2; endspecify endmodule
module top;
timeunit 1ns; timeprecision 1ns;
logic [1:0] a=0; logic c=0; wire y; cell_t u(a,c,y);
initial begin
#5; a=2'b11; #1; if(y!==0) $fatal; #2; if(y!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
