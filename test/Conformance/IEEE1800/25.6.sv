// CLAUSE: interface path terminal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I;logic a=0;wire y;modport M(input a,output y);endinterface
module cell_t(I.M b);assign b.y=b.a;specify(b.a=>b.y)=2;endspecify endmodule
module top;I i();cell_t d(i);initial begin #5;i.a=1;#1;if(i.y!==0)$fatal;#2;if(i.y!==1)$fatal;$display("PASS");$finish;end endmodule
