// CLAUSE: packed 65bit output
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.8.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function void f(output int x);int n;
initial begin
f(n);if(n!=7)$fatal(1,"output");
$display("PASS");$finish;
end
endmodule
