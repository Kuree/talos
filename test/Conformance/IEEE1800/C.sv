// CLAUSE: Legacy features
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf #(parameter N=1);endmodule
module top;leaf d();defparam d.N=3;reg r;reg src=1;
initial begin assign r=src;#1;if(r!==1 || d.N!=3)$fatal(1,"deprecated constructs");deassign r;src=0;#1;if(r!==1)$fatal(1,"deassign");$display("PASS");$finish;end endmodule
