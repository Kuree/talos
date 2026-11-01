// CLAUSE: process self, status, suspend, resume and kill
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;process p;int count=0;
initial begin
 fork begin p=process::self();forever begin #1;count++;end end join_none
 #3;p.suspend();#1;if(p.status()!=process::SUSPENDED)$fatal(1,"suspend status");
 p.resume();#2;p.kill();#1;if(p.status()!=process::KILLED)$fatal(1,"kill status");
 $display("PASS");$finish;
end endmodule
