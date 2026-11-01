// CLAUSE: open array descending
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.1/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function int c35_open_bounds(input int a[],input int l,input int r);int a[7:5]='{10,20,30};
initial begin
if(c35_open_bounds(a,7,5)!=60)$fatal(1,"open bounds");
$display("PASS"); $finish;
end
endmodule
