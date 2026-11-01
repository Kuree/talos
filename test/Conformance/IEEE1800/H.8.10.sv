// CLAUSE: string inout output
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.8.10/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function int c35_strings(inout string s,output string out);string s="before",out;
initial begin
if(c35_strings(s,out)!=1 || s!="after" || out!="output")$fatal(1,"string ABI");
$display("PASS"); $finish;
end
endmodule
