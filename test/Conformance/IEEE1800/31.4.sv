// CLAUSE: width threshold boundary
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module monitor_t(input wire d,clk,en,output logic n=0); timeunit 1ns; timeprecision 1ns; specify $width(posedge clk,3,1,n); endspecify endmodule
module top;
timeunit 1ns; timeprecision 1ns;
logic d=0,clk=0,en=1; wire n; monitor_t u(d,clk,en,n);
initial begin
#5; clk=1; #1; clk=0; #1; if(n!==0) $fatal; #1; clk=1; #2; clk=0; #1; if(n!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
