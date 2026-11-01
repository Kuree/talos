// CLAUSE: optional driver counting
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;wire n;logic a=0,b=1;int f,all,z,o,x;assign n=a;assign n=b;
initial begin #1;if($countdrivers(n,f,all,z,o,x)!=1 || all!=2 || z!=1 || o!=1 || x!=0) $fatal(1,"driver counts");$display("PASS");$finish;end endmodule
