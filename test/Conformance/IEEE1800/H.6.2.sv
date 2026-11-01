// CLAUSE: Input arguments
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.6.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int f(input int x);int n=5;
initial begin
if(f(n)!=6 || n!=5)$fatal(1,"input copy");
$display("PASS");$finish;
end
endmodule
