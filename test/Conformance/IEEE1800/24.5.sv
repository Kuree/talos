// CLAUSE: program calls module task
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

program P;initial begin top.t();#1;if(top.x!=1)$fatal;$display("PASS");$finish;end endprogram
module top;int x=0;P p();task t;x<=1;#0;if(x!=0)$fatal;endtask endmodule
