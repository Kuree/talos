// CLAUSE: Bit-selects used as specify terminals
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

`timescale 1ns/1ns
module child(input wire[1:0]a,output wire[1:0]y);assign y=a;specify (a[0]=>y[0])=2; endspecify endmodule
module top;
bit[1:0]a=0;wire[1:0]y;child u(a,y);
initial begin #3;a=1;#1;if(y[0]!==0)$fatal(1,"result");#2;if(y[0]!==1)$fatal(1,"result"); $display("PASS");end
endmodule
