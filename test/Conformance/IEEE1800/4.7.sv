// CLAUSE: active race allowed results
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;int x;initial x=1;initial x=2;initial begin #1;if(x!=1&&x!=2)$fatal(1,"active race outcome");$display("PASS");$finish;end endmodule
