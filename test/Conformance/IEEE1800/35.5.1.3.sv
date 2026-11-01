// CLAUSE: Instant completion of imported functions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.1.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" pure function int f(input int x);
initial begin
if(f(3)!=9)$fatal(1,"pure result");
$display("PASS");$finish;
end
endmodule
