// CLAUSE: Legacy DPI imports use opaque packed-data handles
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.14/legacy.c -I%resource_dir/include -o %t.legacy.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s %t.legacy.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;import "DPI" function int legacy(input bit[7:0] a);initial begin if(legacy(8'ha5)!=165)$fatal(1,"legacy packed DPI");$display("PASS");$finish;end endmodule
