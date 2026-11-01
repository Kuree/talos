// CLAUSE: Several identifiers in one declaration
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int a,b;
initial begin a=3;b=4;if(a+b!=7)$fatal(1,"result"); $display("PASS");end
endmodule
