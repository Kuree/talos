// CLAUSE: Multiclocked properties
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; timeunit 1ns; timeprecision 1ns;
 bit a=0,b=0; int overlap=0,nonoverlap=0,ot=0,nt=0;
 p:assert property(@(posedge a) 1 |-> @(posedge b) 1) begin overlap++;ot=$time;end else $fatal;
 q:assert property(@(posedge a) 1 |=> @(posedge b) 1) begin nonoverlap++;nt=$time;end else $fatal;
 initial begin #1;a=1;b=1;#1;if(overlap!=1 || ot!=1 || nonoverlap!=0)$fatal; b=0;
 #1;b=1;#1;if(nonoverlap!=1 || nt!=3)$fatal;$display("PASS");$finish;end
endmodule
