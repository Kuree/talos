// CLAUSE: Fixed DPI arrays use lower indices first in C
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.11/array.c -I%resource_dir/include -o %t.array.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.array.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;import "DPI-C" function int first(input int a[5:3]);int a[5:3]='{7,8,9};initial begin if(first(a)!=9)$fatal(1,"normalized fixed array");$display("PASS");$finish;end endmodule
