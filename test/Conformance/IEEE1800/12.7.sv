// CLAUSE: A foreach loop executes its element statements
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;int a[2]='{1,2};int sum;
initial begin foreach(a[i])sum+=a[i];if(sum!=3)$fatal(1,"loop execution");$display("PASS");$finish;end endmodule
