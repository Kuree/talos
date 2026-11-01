// CLAUSE: longest static prefix
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;logic[7:0]a[2];int i=0;logic y;always_comb y=a[i][0];initial begin a='{0,1};#1;if(y!==0)$fatal;i=1;#1;if(y!==1)$fatal;a[1][0]=0;#1;if(y!==0)$fatal;$display("PASS");$finish;end endmodule
