// CLAUSE: Separate rise and fall path delays
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

`timescale 1ns/1ns
module child(input wire a,output wire y);assign y=a;specify (a=>y)=(2,3); endspecify endmodule
module top;
bit a=0;wire y;child u(a,y);
initial begin #4;a=1;#1;if(y!==0)$fatal(1,"result");#2;if(y!==1)$fatal(1,"result");a=0;#2;if(y!==1)$fatal(1,"result");#2;if(y!==0)$fatal(1,"result"); $display("PASS");end
endmodule
