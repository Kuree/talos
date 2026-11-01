// CLAUSE: DPI call arguments are coerced to the declared formal type
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.6/coerce.c -I%resource_dir/include -o %t.coerce.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.coerce.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;import "DPI-C" function int f(input byte a);int x=257;initial begin if(f(x)!=1)$fatal(1,"DPI actual coercion");$display("PASS");$finish;end endmodule
