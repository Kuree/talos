// CLAUSE: dpi time scope api
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.13/dpi_time_min.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" context function int c35_time_min();
initial begin
if(c35_time_min()!=1)$fatal(1,"DPI time unit");
$display("PASS"); $finish;
end
endmodule
