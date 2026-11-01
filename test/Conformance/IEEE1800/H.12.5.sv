// CLAUSE: Access to elements via canonical representation
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int f(input bit[3:0] a[]);bit[3:0] a[1]='{4'ha};
initial begin
if(f(a)!=10)$fatal(1,"canonical open array");
$display("PASS");$finish;
end
endmodule
