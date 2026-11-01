// CLAUSE: open array matrix
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.8/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function int c35_open_matrix(input int a[][]);int a[2:1][-1:1]='{'{1,2,3},'{4,5,6}};
initial begin
if(c35_open_matrix(a)!=21)$fatal(1,"matrix ABI");
$display("PASS"); $finish;
end
endmodule
