// CLAUSE: Direct access to unpacked arrays
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int f(input int a[]);int a[2]='{4,5};
initial begin
if(!f(a))$fatal(1,"direct representation");
$display("PASS");$finish;
end
endmodule
