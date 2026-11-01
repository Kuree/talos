// CLAUSE: Access to scalar elements (bit and logic)
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.6/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int f(input logic a[]);logic a[1]='{1'bz};
initial begin
if(!f(a))$fatal(1,"logic element");
$display("PASS");$finish;
end
endmodule
