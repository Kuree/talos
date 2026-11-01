// CLAUSE: SV scalar types cross the C boundary
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.2.2/abi.c -I%resource_dir/include -o %t.abi.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.abi.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
import "DPI-C" function int f(input int a,output int b,inout int c);
int b,c=3;initial begin if(f(2,b,c)!=5||b!=4||c!=4)$fatal(1,"DPI ABI");$display("PASS");$finish;end endmodule
