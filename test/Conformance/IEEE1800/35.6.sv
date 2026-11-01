// CLAUSE: DPI calls support named and default arguments
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.6/call.c -I%resource_dir/include -o %t.call.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.call.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;import "DPI-C" function int f(input int a=2,b=3);initial begin if(f(.b(4))!=24)$fatal(1,"named/default DPI call");$display("PASS");$finish;end endmodule
