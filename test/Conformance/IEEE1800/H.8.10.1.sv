// CLAUSE: String types in aggregate arguments
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.8.10.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {string s;}T;import "DPI-C" function void f(inout T x);T t;
initial begin
t.s="a";f(t);if(t.s!="z")$fatal(1,"string field");
$display("PASS");$finish;
end
endmodule
