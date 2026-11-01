// CLAUSE: Unary and binary operators form expressions
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;int a=3,b=2;
initial begin if(((a+b)*b)!=10||!a)$fatal(1,"operator forms");$display("PASS");$finish;end endmodule
