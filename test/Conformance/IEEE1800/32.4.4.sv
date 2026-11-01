// CLAUSE: SDF annotation of interconnect delays
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ns
module source(input wire a,output wire o);assign o=a;endmodule
module sink(input wire i,output wire o);assign o=i;endmodule
module top;timeunit 1ns;timeprecision 1ns;logic a=0;wire n,q;source src(a,n);sink dst(n,q);initial begin $sdf_annotate("delay.sdf",top);#5;a=1;#1;if(q!==0)$fatal(1,"early port");#3;if(q!==1)$fatal(1,"late port");$display("PASS");$finish;end endmodule
